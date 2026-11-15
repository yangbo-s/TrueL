import AppKit
import Foundation
let root=URL(fileURLWithPath:CommandLine.arguments[1])
let variants=try! JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("variants.json"))) as! [[String:Any]]
let width=1536,height=1280
let sheet=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:sheet)
NSColor(srgbRed:0.90,green:0.91,blue:0.91,alpha:1).setFill(); NSRect(x:0,y:0,width:width,height:height).fill()
func text(_ s:String,_ x:CGFloat,_ y:CGFloat,_ size:CGFloat,_ bold:Bool=false,_ centered:Bool=false,_ secondary:Bool=false){
 let attrs:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:size,weight:bold ? .semibold:.regular),.foregroundColor:secondary ? NSColor(white:0.37,alpha:1):NSColor(white:0.07,alpha:1)]
 let str=s as NSString;let extent=str.size(withAttributes:attrs)
 str.draw(at:NSPoint(x:centered ? x-extent.width/2:x,y:CGFloat(height)-y-extent.height),withAttributes:attrs)
}
func draw(_ filename:String,_ x:CGFloat,_ y:CGFloat,_ size:CGFloat){
 let data=try! Data(contentsOf:root.appendingPathComponent("renders").appendingPathComponent(filename));let rep=NSBitmapImageRep(data:data)!
 let img=NSImage(size:NSSize(width:rep.pixelsWide,height:rep.pixelsHigh)); img.addRepresentation(rep)
 img.draw(in:NSRect(x:x,y:CGFloat(height)-y-size,width:size,height:size),from:.zero,operation:.sourceOver,fraction:1)
}
text("TrueL",64,40,34,true); text("六款字体细化 · macOS 原生图标预览",192,50,18,false,false,true)
for (i,v) in variants.enumerated(){
 let col=i%3,row=i/3;let cx=CGFloat(304+col*464),top=CGFloat(144+row*584)
 let id=v["id"] as! String,name=v["name"] as! String,font=v["font"] as! String
 if col==0 {text(row==0 ? "01  联字":"03  句读",64,top-48,18,true)}
 draw(id+".png",cx-136,top,272)
 text(id+" · "+name,cx,top+296,23,true,true)
 text(font,cx,top+330,16,false,true,true)
 for (size,offset) in [(64,-116),(32,-12),(16,76)]{
  let x=cx+CGFloat(offset); draw(id+"-\(size).png",x,top+432-CGFloat(size),CGFloat(size))
  text("\(size)",x+CGFloat(size)/2,top+444,12,false,true,true)
 }
}
text("同一白色底板 · 黑 / 青绿 · 字形来自原字体轮廓",64,1224,15,false,false,true)
NSGraphicsContext.current=nil
let png=sheet.representation(using:.png,properties:[:])!;try! png.write(to:root.appendingPathComponent("comparison.png"))
let cg=sheet.cgImage!
for (name,y,h) in [("01-ligatures",0,650),("03-quotes",660,620)]{
 let crop=cg.cropping(to:CGRect(x:0,y:y,width:width,height:h))!
 let rep=NSBitmapImageRep(cgImage:crop)
 try! rep.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent(name+".png"))
}
print("Wrote comparison.png and two detail sheets")
