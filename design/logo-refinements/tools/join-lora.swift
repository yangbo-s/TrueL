import Foundation
import CoreText
import CoreGraphics
// Join real font contours at their coincident straight stem, not by layering serifs.
func n(_ v:CGFloat)->String {String(format:"%.4f",Double(v))}
func svg(_ path:CGPath)->String {
 var pieces=[String]()
 path.applyWithBlock { pointer in
  let e=pointer.pointee
  func p(_ i:Int)->String {n(e.points[i].x)+" "+n(e.points[i].y)}
  switch e.type {
  case .moveToPoint: pieces.append("M"+p(0))
  case .addLineToPoint: pieces.append("L"+p(0))
  case .addQuadCurveToPoint: pieces.append("Q"+p(0)+" "+p(1))
  case .addCurveToPoint: pieces.append("C"+p(0)+" "+p(1)+" "+p(2))
  case .closeSubpath: pieces.append("Z")
  @unknown default: fatalError("Unsupported curve")
  }
 }
 return pieces.joined(separator:" ")
}
let root=URL(fileURLWithPath:CommandLine.arguments[1])
let descriptors=CTFontManagerCreateFontDescriptorsFromURL(root.appendingPathComponent("fonts/lora/Lora[wght].ttf") as CFURL) as! [CTFontDescriptor]
let original=CTFontCreateWithFontDescriptor(descriptors[0],1000,nil)
let settings=[kCTFontVariationAttribute:[NSNumber(value:0x77676874):NSNumber(value:700)]] as CFDictionary
let font=CTFontCreateWithFontDescriptor(CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(original),settings),1000,nil)
func glyph(_ character:String,_ dx:CGFloat)->CGPath {
 var utf16=Array(character.utf16),g=CGGlyph()
 precondition(CTFontGetGlyphsForCharacters(font,&utf16,&g,1))
 var transform=CGAffineTransform(a:1,b:0,c:0,d:-1,tx:dx,ty:0)
 return CTFontCreatePathForGlyph(font,g,nil)!.copy(using:&transform)!
}
let t=glyph("T",0), l=glyph("L",130), split:CGFloat = -350
// Keep source curve segments verbatim. Only straight lines cross the splice.
struct Segment {
 let start:CGPoint
 let end:CGPoint
 let controls:[CGPoint]
}
func segments(_ path:CGPath, upper:Bool)->[Segment] {
 var result=[Segment](),current=CGPoint.zero,origin=CGPoint.zero
 func keep(_ end:CGPoint,_ controls:[CGPoint]=[]) {
  let segment=Segment(start:current,end:end,controls:controls)
  defer {current=end}
  let ys=([current,end]+controls).map(\.y)
  if ys.max()! <= split { if upper {result.append(segment)}; return }
  if ys.min()! >= split { if !upper {result.append(segment)}; return }
  precondition(controls.isEmpty,"A source curve crosses the proposed straight-stem cut")
  let amount=(split-current.y)/(end.y-current.y)
  let intersection=CGPoint(x:current.x+(end.x-current.x)*amount,y:split)
  if (current.y<split)==upper {result.append(Segment(start:current,end:intersection,controls:[]))}
  else {result.append(Segment(start:intersection,end:end,controls:[]))}
 }
 path.applyWithBlock { ptr in
  let e=ptr.pointee
  switch e.type {
  case .moveToPoint: current=e.points[0];origin=current
  case .addLineToPoint: keep(e.points[0])
  case .addQuadCurveToPoint: keep(e.points[1],[e.points[0]])
  case .addCurveToPoint: keep(e.points[2],[e.points[0],e.points[1]])
  case .closeSubpath: if current != origin {keep(origin)}
  @unknown default: fatalError("Unsupported segment")
  }
 }
 return result
}
var remaining=segments(t,upper:true)+segments(l,upper:false)
let joined=CGMutablePath(),start=CGPoint(x:396,y:split)
joined.move(to:start)
var cursor=start,sourceCurves=0
while !remaining.isEmpty {
 guard let index=remaining.firstIndex(where:{$0.start==cursor}) else {fatalError("Disconnected source outlines")}
 let s=remaining.remove(at:index)
 switch s.controls.count {
 case 0: joined.addLine(to:s.end)
 case 1: joined.addQuadCurve(to:s.end,control:s.controls[0]);sourceCurves += 1
 case 2: joined.addCurve(to:s.end,control1:s.controls[0],control2:s.controls[1]);sourceCurves += 1
 default: fatalError("Unexpected curve")
 }
 cursor=s.end
}
precondition(cursor==start,"Open contour")
joined.closeSubpath()
// Verify that the two true stems coincide around the splice and the result is exact.
for y in stride(from:split-10,through:split+10,by:0.5) {
 for x in stride(from:CGFloat(240),through:CGFloat(408),by:0.5) {
  let p=CGPoint(x:x,y:y)
  precondition(t.contains(p)==l.contains(p),"Font stems do not coincide at the join")
 }
}
var compared=0
for y in stride(from:CGFloat(-699.75),through:CGFloat(-0.25),by:0.5) {
 for x in stride(from:CGFloat(15.75),through:CGFloat(720.25),by:0.5) {
  let p=CGPoint(x:x,y:y)
  precondition(joined.contains(p)==(y<split ? t:l).contains(p),"Splice changed the selected font outline")
  compared += 1
 }
}
var moves=0
joined.applyWithBlock {if $0.pointee.type == .moveToPoint {moves += 1}}
precondition(moves==1,"Expected a single connected outer contour")
let result:[String:Any] = ["family":"lora","weight":700,"sourceGlyphs":["T","L"],"LTranslationX":130,"splitY":split,"stemX":[251,396],"d":svg(joined),"closedContours":moves,"originalCurvesPreserved":sourceCurves,"verifiedSamples":compared]
try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("1C-contour.json"))
print("PASS one continuous contour; equal vertical tangents at the join; \(compared) source-shape samples matched")
