import Foundation
import CoreText
import CoreGraphics
func number(_ n: CGFloat)->String { String(format:"%.4f",Double(n)) }
func svgPath(_ path: CGPath)->String {
 var chunks=[String]()
 path.applyWithBlock { pointer in
  let e=pointer.pointee
  func p(_ i:Int)->String { number(e.points[i].x)+" "+number(e.points[i].y) }
  switch e.type {
  case .moveToPoint: chunks.append("M"+p(0))
  case .addLineToPoint: chunks.append("L"+p(0))
  case .addQuadCurveToPoint: chunks.append("Q"+p(0)+" "+p(1))
  case .addCurveToPoint: chunks.append("C"+p(0)+" "+p(1)+" "+p(2))
  case .closeSubpath: chunks.append("Z")
  @unknown default: fatalError("Unsupported curve")
  }
 }
 return chunks.joined(separator:" ")
}
func stem(_ path:CGPath,_ b:CGRect)->[CGFloat] {
 let y=b.minY+b.height*0.5
 let samples=stride(from:b.minX,through:b.maxX,by:0.25).filter { path.contains(CGPoint(x:$0,y:y)) }
 return [samples.first ?? b.minX,samples.last ?? b.maxX]
}
let base=URL(fileURLWithPath:CommandLine.arguments[1])
var result=[[String:Any]]()
for (family, file, weight) in [("inter","Inter[opsz,wght].ttf",800),("manrope","Manrope[wght].ttf",800),("lora","Lora[wght].ttf",700),("sourceserif4","SourceSerif4[opsz,wght].ttf",900)] {
 let url=base.appendingPathComponent(family).appendingPathComponent(file)
 let descriptors=CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as! [CTFontDescriptor]
 let original=CTFontCreateWithFontDescriptor(descriptors[0],1000,nil)
 let variation=[NSNumber(value:0x77676874):NSNumber(value:weight),NSNumber(value:0x6F70737A):NSNumber(value:24)]
 let descriptor=CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(original),[kCTFontVariationAttribute:variation] as CFDictionary)
 let font=CTFontCreateWithFontDescriptor(descriptor,1000,nil)
 for char in ["T","L","‘","’","“","”"] {
  var utf16=Array(char.utf16);var glyph=CGGlyph()
  guard CTFontGetGlyphsForCharacters(font,&utf16,&glyph,1), let raw=CTFontCreatePathForGlyph(font,glyph,nil) else {fatalError("Missing glyph \(family) \(char)")}
  var flip=CGAffineTransform(scaleX:1,y:-1)
  let path=raw.copy(using:&flip)!
  let b=path.boundingBoxOfPath
  result.append(["family":family,"fontName":CTFontCopyPostScriptName(font),"weight":weight,"char":char,"glyph":Int(glyph),"d":svgPath(path),"bounds":[b.minX,b.minY,b.width,b.height],"stem":stem(path,b)])
 }
}
let data=try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys])
try data.write(to:base.deletingLastPathComponent().appendingPathComponent("glyphs.json"))
print("Exported \(result.count) actual CoreText glyph outlines")
