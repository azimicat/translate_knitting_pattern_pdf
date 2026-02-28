import CoreGraphics
import Foundation
import ImageIO

// MARK: - ExtractedImage

struct ExtractedImage: Sendable {
    let image: CGImage
    let pageIndex: Int
    let bounds: CGRect
}

// MARK: - ScannerContext (must be a pure value type for UnsafeMutablePointer safety)

struct ScannerContext {
    var ctmStack: [CGAffineTransform] = [.identity]
    var currentCTM: CGAffineTransform = .identity
    var images: [ExtractedImage] = []
    var pageIndex: Int = 0
    var pageHeight: CGFloat = 0
    // Store the XObject dictionary for lookup in op_Do
    var xObjectDict: CGPDFDictionaryRef? = nil
}

// MARK: - File-scope C callbacks (cannot capture, use info pointer)

func pdfOp_q(_ scanner: CGPDFScannerRef, _ info: UnsafeMutableRawPointer?) {
    let ctx = info!.assumingMemoryBound(to: ScannerContext.self)
    ctx.pointee.ctmStack.append(ctx.pointee.currentCTM)
}

func pdfOp_Q(_ scanner: CGPDFScannerRef, _ info: UnsafeMutableRawPointer?) {
    let ctx = info!.assumingMemoryBound(to: ScannerContext.self)
    if let prev = ctx.pointee.ctmStack.popLast() {
        ctx.pointee.currentCTM = prev
    }
}

func pdfOp_cm(_ scanner: CGPDFScannerRef, _ info: UnsafeMutableRawPointer?) {
    // PDF "cm" pushes a b c d e f; scanner stack is LIFO → pop f e d c b a
    var f: CGPDFReal = 0
    var e: CGPDFReal = 0
    var d: CGPDFReal = 0
    var c: CGPDFReal = 0
    var b: CGPDFReal = 0
    var a: CGPDFReal = 0
    guard CGPDFScannerPopNumber(scanner, &f),
          CGPDFScannerPopNumber(scanner, &e),
          CGPDFScannerPopNumber(scanner, &d),
          CGPDFScannerPopNumber(scanner, &c),
          CGPDFScannerPopNumber(scanner, &b),
          CGPDFScannerPopNumber(scanner, &a) else { return }
    let m = CGAffineTransform(
        a: CGFloat(a), b: CGFloat(b),
        c: CGFloat(c), d: CGFloat(d),
        tx: CGFloat(e), ty: CGFloat(f)
    )
    let ctx = info!.assumingMemoryBound(to: ScannerContext.self)
    // Post-multiply: new CTM = current * m (PDF matrix composition)
    ctx.pointee.currentCTM = ctx.pointee.currentCTM.concatenating(m)
}

func pdfOp_Do(_ scanner: CGPDFScannerRef, _ info: UnsafeMutableRawPointer?) {
    var name: UnsafePointer<CChar>? = nil
    guard CGPDFScannerPopName(scanner, &name), let name else { return }
    let ctx = info!.assumingMemoryBound(to: ScannerContext.self)
    guard let xDict = ctx.pointee.xObjectDict else { return }

    // Look up name in XObject dict
    var streamRef: CGPDFStreamRef? = nil
    guard CGPDFDictionaryGetStream(xDict, name, &streamRef), let stream = streamRef else { return }
    let streamDict = CGPDFStreamGetDictionary(stream)!

    // Must be /Subtype /Image
    var subtypeName: UnsafePointer<CChar>? = nil
    guard CGPDFDictionaryGetName(streamDict, "Subtype", &subtypeName),
          let subtypeName, String(cString: subtypeName) == "Image" else { return }

    var width: CGPDFInteger = 0
    var height: CGPDFInteger = 0
    CGPDFDictionaryGetInteger(streamDict, "Width", &width)
    CGPDFDictionaryGetInteger(streamDict, "Height", &height)

    // Skip images with long side ≤ 80px (icons, decorations)
    guard max(width, height) > 80 else { return }

    // Extract pixel data
    var format = CGPDFDataFormat.raw
    guard let cfData = CGPDFStreamCopyData(stream, &format) else { return }

    let cgImage: CGImage?
    if format == .jpegEncoded || format == .JPEG2000 {
        // Use ImageIO for JPEG/JPEG2000
        let src = CGImageSourceCreateWithData(cfData, nil)
        cgImage = src.flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    } else {
        // Raw pixel data: construct CGImage from color space info
        var bpc: CGPDFInteger = 8
        CGPDFDictionaryGetInteger(streamDict, "BitsPerComponent", &bpc)
        var csNamePtr: UnsafePointer<CChar>? = nil
        let colorSpace: CGColorSpace
        if CGPDFDictionaryGetName(streamDict, "ColorSpace", &csNamePtr), let csn = csNamePtr {
            switch String(cString: csn) {
            case "DeviceGray": colorSpace = CGColorSpaceCreateDeviceGray()
            case "DeviceCMYK": colorSpace = CGColorSpaceCreateDeviceCMYK()
            default:           colorSpace = CGColorSpaceCreateDeviceRGB()
            }
        } else {
            colorSpace = CGColorSpaceCreateDeviceRGB()
        }
        let nComp = colorSpace.numberOfComponents
        cgImage = CGImage(
            width: Int(width),
            height: Int(height),
            bitsPerComponent: Int(bpc),
            bitsPerPixel: Int(bpc) * nComp,
            bytesPerRow: Int(width) * nComp * Int(bpc) / 8,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: CGDataProvider(data: cfData)!,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
    guard let cgImage else { return }

    // Image bounds on page: CTM transforms unit square [0,1]×[0,1]
    // standardized で負の height（flip transform 由来）を正規化する
    let imgBoundsOnPage = CGRect(x: 0, y: 0, width: 1, height: 1)
        .applying(ctx.pointee.currentCTM)
        .standardized

    // 画像全体がヘッダーゾーン（上位10%）またはフッターゾーン（下位10%）に
    // 完全に収まる場合のみ除外する。
    // PDF coords: y=0 = bottom, y=pageHeight = top
    let pH = ctx.pointee.pageHeight
    if imgBoundsOnPage.minY > pH * 0.90 || imgBoundsOnPage.maxY < pH * 0.10 { return }

    ctx.pointee.images.append(ExtractedImage(
        image: cgImage,
        pageIndex: ctx.pointee.pageIndex,
        bounds: imgBoundsOnPage
    ))
}

// MARK: - Actor

actor ImageExtractor {
    func extractImages(from url: URL) async throws -> [ExtractedImage] {
        guard let pdfDoc = CGPDFDocument(url as CFURL) else { return [] }

        // Build operator table once
        let table = CGPDFOperatorTableCreate()!
        CGPDFOperatorTableSetCallback(table, "q",  pdfOp_q)
        CGPDFOperatorTableSetCallback(table, "Q",  pdfOp_Q)
        CGPDFOperatorTableSetCallback(table, "cm", pdfOp_cm)
        CGPDFOperatorTableSetCallback(table, "Do", pdfOp_Do)

        var allImages: [ExtractedImage] = []

        for pageNum in 1...pdfDoc.numberOfPages {
            guard let page = pdfDoc.page(at: pageNum) else { continue }
            let mediaBox = page.getBoxRect(.mediaBox)

            // Resolve XObject dict for this page
            var xObjDict: CGPDFDictionaryRef? = nil
            if let pageDict = page.dictionary {
                var resDict: CGPDFDictionaryRef? = nil
                if CGPDFDictionaryGetDictionary(pageDict, "Resources", &resDict),
                   let res = resDict {
                    CGPDFDictionaryGetDictionary(res, "XObject", &xObjDict)
                }
            }

            // Heap-allocate context (stack address would become dangling during scan)
            let ctxPtr = UnsafeMutablePointer<ScannerContext>.allocate(capacity: 1)
            ctxPtr.initialize(to: ScannerContext(
                pageIndex: pageNum - 1,
                pageHeight: mediaBox.height,
                xObjectDict: xObjDict
            ))
            defer {
                ctxPtr.deinitialize(count: 1)
                ctxPtr.deallocate()
            }

            let stream = CGPDFContentStreamCreateWithPage(page)
            let scanner = CGPDFScannerCreate(stream, table, UnsafeMutableRawPointer(ctxPtr))
            CGPDFScannerScan(scanner)
            CGPDFScannerRelease(scanner)
            CGPDFContentStreamRelease(stream)

            allImages.append(contentsOf: ctxPtr.pointee.images)
        }
        return allImages
    }
}
