import CoreGraphics
import Foundation
import ImageIO

// MARK: - ExtractedImage

struct ExtractedImage: Sendable {
    let image: CGImage
    let pageIndex: Int
}

// MARK: - ScannerContext (class で参照共有・再帰対応)

final class ScannerContext {
    var ctmStack: [CGAffineTransform] = []
    var currentCTM: CGAffineTransform
    var images: [ExtractedImage] = []
    var xObjectDict: CGPDFDictionaryRef?
    let pageIndex: Int
    let pageHeight: CGFloat
    let operatorTable: CGPDFOperatorTableRef
    /// ページのコンテンツストリーム（Form XObject のリソース継承に使用）
    /// スキャン中のみ有効（Release後はnil）
    var pageContentStream: CGPDFContentStreamRef? = nil

    init(pageIndex: Int,
         pageHeight: CGFloat,
         xObjectDict: CGPDFDictionaryRef?,
         operatorTable: CGPDFOperatorTableRef,
         startCTM: CGAffineTransform = .identity) {
        self.pageIndex      = pageIndex
        self.pageHeight     = pageHeight
        self.xObjectDict    = xObjectDict
        self.operatorTable  = operatorTable
        self.currentCTM     = startCTM
    }
}

// MARK: - File-scope C callbacks

func pdfOp_q(_ scanner: CGPDFScannerRef, _ info: UnsafeMutableRawPointer?) {
    let ctx = Unmanaged<ScannerContext>.fromOpaque(info!).takeUnretainedValue()
    ctx.ctmStack.append(ctx.currentCTM)
}

func pdfOp_Q(_ scanner: CGPDFScannerRef, _ info: UnsafeMutableRawPointer?) {
    let ctx = Unmanaged<ScannerContext>.fromOpaque(info!).takeUnretainedValue()
    if let saved = ctx.ctmStack.popLast() { ctx.currentCTM = saved }
}

func pdfOp_cm(_ scanner: CGPDFScannerRef, _ info: UnsafeMutableRawPointer?) {
    var f: CGPDFReal = 0, e: CGPDFReal = 0, d: CGPDFReal = 0
    var c: CGPDFReal = 0, b: CGPDFReal = 0, a: CGPDFReal = 0
    guard CGPDFScannerPopNumber(scanner, &f),
          CGPDFScannerPopNumber(scanner, &e),
          CGPDFScannerPopNumber(scanner, &d),
          CGPDFScannerPopNumber(scanner, &c),
          CGPDFScannerPopNumber(scanner, &b),
          CGPDFScannerPopNumber(scanner, &a) else { return }
    let m = CGAffineTransform(a: CGFloat(a), b: CGFloat(b),
                               c: CGFloat(c), d: CGFloat(d),
                               tx: CGFloat(e), ty: CGFloat(f))
    let ctx = Unmanaged<ScannerContext>.fromOpaque(info!).takeUnretainedValue()
    ctx.currentCTM = ctx.currentCTM.concatenating(m)
}

func pdfOp_Do(_ scanner: CGPDFScannerRef, _ info: UnsafeMutableRawPointer?) {
    var name: UnsafePointer<CChar>? = nil
    guard CGPDFScannerPopName(scanner, &name), let name else { return }
    let ctx = Unmanaged<ScannerContext>.fromOpaque(info!).takeUnretainedValue()
    guard let xDict = ctx.xObjectDict else { return }

    var streamRef: CGPDFStreamRef? = nil
    guard CGPDFDictionaryGetStream(xDict, name, &streamRef),
          let stream = streamRef else { return }
    let streamDict = CGPDFStreamGetDictionary(stream)!

    var subtypePtr: UnsafePointer<CChar>? = nil
    guard CGPDFDictionaryGetName(streamDict, "Subtype", &subtypePtr),
          let subtypePtr else { return }

    switch String(cString: subtypePtr) {
    case "Image":
        extractImageXObject(stream: stream, dict: streamDict, ctx: ctx)
    case "Form":
        processFormXObject(stream: stream, dict: streamDict, parentCtx: ctx)
    default:
        break
    }
}

// MARK: - Image extraction helper

func extractImageXObject(stream: CGPDFStreamRef, dict: CGPDFDictionaryRef, ctx: ScannerContext) {
    var width: CGPDFInteger = 0
    var height: CGPDFInteger = 0
    CGPDFDictionaryGetInteger(dict, "Width",  &width)
    CGPDFDictionaryGetInteger(dict, "Height", &height)

    // 短辺 80px 以下の小画像（アイコン・装飾）を除外
    guard min(width, height) > 80 else { return }

    // CTM でページ上の配置矩形を求める（y-up 座標系）
    let bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        .applying(ctx.currentCTM)
        .standardized

    // 上部 10% に完全に収まる → ヘッダー除外
    // 下部 10% に完全に収まる → フッター除外
    let pH = ctx.pageHeight
    if bounds.minY > pH * 0.90 { return }
    if bounds.maxY < pH * 0.10 { return }

    // ピクセルデータを取得
    var format = CGPDFDataFormat.raw
    guard let cfData = CGPDFStreamCopyData(stream, &format) else { return }

    let cgImage: CGImage?
    if format == .jpegEncoded || format == .JPEG2000 {
        let src = CGImageSourceCreateWithData(cfData, nil)
        cgImage = src.flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    } else {
        var bpc: CGPDFInteger = 8
        CGPDFDictionaryGetInteger(dict, "BitsPerComponent", &bpc)
        var csNamePtr: UnsafePointer<CChar>? = nil
        let colorSpace: CGColorSpace
        if CGPDFDictionaryGetName(dict, "ColorSpace", &csNamePtr), let csn = csNamePtr {
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
            width: Int(width), height: Int(height),
            bitsPerComponent: Int(bpc),
            bitsPerPixel: Int(bpc) * nComp,
            bytesPerRow: Int(width) * nComp * Int(bpc) / 8,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: CGDataProvider(data: cfData)!,
            decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }
    guard let img = cgImage else { return }
    ctx.images.append(ExtractedImage(image: img, pageIndex: ctx.pageIndex))
}

// MARK: - Form XObject recursive processing

func processFormXObject(stream: CGPDFStreamRef, dict: CGPDFDictionaryRef, parentCtx: ScannerContext) {
    // Form の Matrix 属性（省略時は単位行列）
    var formMatrix: CGAffineTransform = .identity
    var matArr: CGPDFArrayRef? = nil
    if CGPDFDictionaryGetArray(dict, "Matrix", &matArr), let arr = matArr {
        var a: CGPDFReal = 1, b: CGPDFReal = 0, c: CGPDFReal = 0
        var d: CGPDFReal = 1, e: CGPDFReal = 0, f: CGPDFReal = 0
        CGPDFArrayGetNumber(arr, 0, &a); CGPDFArrayGetNumber(arr, 1, &b)
        CGPDFArrayGetNumber(arr, 2, &c); CGPDFArrayGetNumber(arr, 3, &d)
        CGPDFArrayGetNumber(arr, 4, &e); CGPDFArrayGetNumber(arr, 5, &f)
        formMatrix = CGAffineTransform(a: CGFloat(a), b: CGFloat(b),
                                        c: CGFloat(c), d: CGFloat(d),
                                        tx: CGFloat(e), ty: CGFloat(f))
    }

    // Form の Resources から XObject dict を取得
    var formResources: CGPDFDictionaryRef? = nil
    var formXObjDict: CGPDFDictionaryRef? = nil
    if CGPDFDictionaryGetDictionary(dict, "Resources", &formResources),
       let res = formResources {
        CGPDFDictionaryGetDictionary(res, "XObject", &formXObjDict)
    }

    // Form 内で CTM を引き継いだサブコンテキストを生成
    let subCtx = ScannerContext(
        pageIndex:     parentCtx.pageIndex,
        pageHeight:    parentCtx.pageHeight,
        xObjectDict:   formXObjDict ?? parentCtx.xObjectDict,
        operatorTable: parentCtx.operatorTable,
        startCTM:      parentCtx.currentCTM.concatenating(formMatrix)
    )

    // Form のリソースが取得できない場合はスキップ
    guard let formRes = formResources else { return }
    // ページのコンテンツストリームをリソース継承の親として渡す
    guard let parent = parentCtx.pageContentStream else { return }

    // Form のコンテンツストリームをスキャン
    let formStream = CGPDFContentStreamCreateWithStream(stream, formRes, parent)
    let ptr = Unmanaged.passRetained(subCtx).toOpaque()
    let formScanner = CGPDFScannerCreate(formStream, parentCtx.operatorTable, ptr)
    CGPDFScannerScan(formScanner)
    CGPDFScannerRelease(formScanner)
    CGPDFContentStreamRelease(formStream)
    Unmanaged<ScannerContext>.fromOpaque(ptr).release()

    // サブコンテキストの画像を親へマージ
    parentCtx.images.append(contentsOf: subCtx.images)
}

// MARK: - Actor

actor ImageExtractor {
    func extractImages(from url: URL) async throws -> [ExtractedImage] {
        guard let pdfDoc = CGPDFDocument(url as CFURL) else { return [] }

        let table = CGPDFOperatorTableCreate()!
        CGPDFOperatorTableSetCallback(table, "q",  pdfOp_q)
        CGPDFOperatorTableSetCallback(table, "Q",  pdfOp_Q)
        CGPDFOperatorTableSetCallback(table, "cm", pdfOp_cm)
        CGPDFOperatorTableSetCallback(table, "Do", pdfOp_Do)

        var allImages: [ExtractedImage] = []

        for pageNum in 1...pdfDoc.numberOfPages {
            guard let page = pdfDoc.page(at: pageNum) else { continue }
            let mediaBox = page.getBoxRect(.mediaBox)

            // ページの XObject 辞書を取得
            var xObjDict: CGPDFDictionaryRef? = nil
            if let pageDict = page.dictionary {
                var resDict: CGPDFDictionaryRef? = nil
                if CGPDFDictionaryGetDictionary(pageDict, "Resources", &resDict),
                   let res = resDict {
                    CGPDFDictionaryGetDictionary(res, "XObject", &xObjDict)
                }
            }

            let ctx = ScannerContext(
                pageIndex:    pageNum - 1,
                pageHeight:   mediaBox.height,
                xObjectDict:  xObjDict,
                operatorTable: table
            )

            let contentStream = CGPDFContentStreamCreateWithPage(page)
            // スキャン中のみ有効な参照としてコンテキストに保持（Form XObject の親継承用）
            ctx.pageContentStream = contentStream
            let ptr = Unmanaged.passRetained(ctx).toOpaque()
            let scanner = CGPDFScannerCreate(contentStream, table, ptr)
            CGPDFScannerScan(scanner)
            CGPDFScannerRelease(scanner)
            ctx.pageContentStream = nil  // Release前にクリア
            CGPDFContentStreamRelease(contentStream)
            Unmanaged<ScannerContext>.fromOpaque(ptr).release()

            allImages.append(contentsOf: ctx.images)
        }

        return allImages
    }
}
