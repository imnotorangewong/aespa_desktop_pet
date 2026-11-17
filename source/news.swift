import AppKit
import UniformTypeIdentifiers

struct TongjiNotice:Codable {let title:String;let date:String;var pinned:Bool=false}
struct TongjiSnapshot:Codable {let updatedAt:String;let notices:[TongjiNotice]}
final class TongjiNewsController:NSObject {
    let panel:ChatPanel
    let stack=NSStackView()
    let status=NSTextField(labelWithString:"")
    var snapshot:TongjiSnapshot?
    var owner:NSWindow
    let origin=URL(string:"https://1.tongji.edu.cn/workbench")!
    let cacheURL=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("imnotorange-pet/tongji-notices.json")
    init(owner:NSWindow) {
        self.owner=owner
        panel=ChatPanel(contentRect:NSRect(x:0,y:0,width:400,height:420),styleMask:[.borderless],backing:.buffered,defer:false)
        super.init()
        panel.title="同济news";panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=true;panel.level = .floating;panel.hidesOnDeactivate=false
        let content=DragBackgroundView(frame:NSRect(x:0,y:0,width:400,height:420))
        if #available(macOS 26.0,*) {let glass=NSGlassEffectView(frame:content.bounds);glass.cornerRadius=26;glass.contentView=content;panel.contentView=glass}
        else {let effect=NSVisualEffectView(frame:content.bounds);effect.material = .popover;effect.state = .active;effect.addSubview(content);panel.contentView=effect}
        let title=NSTextField(labelWithString:"同济news");title.font = .systemFont(ofSize:18,weight:.semibold);title.frame=NSRect(x:20,y:378,width:270,height:28);content.addSubview(title)
        let close=NSButton(title:"×",target:self,action:#selector(hide));close.frame=NSRect(x:352,y:376,width:28,height:28);close.bezelStyle = .circular;content.addSubview(close)
        status.frame=NSRect(x:20,y:346,width:360,height:28);status.font = .systemFont(ofSize:10);status.textColor = .secondaryLabelColor;content.addSubview(status)
        let scroll=NSScrollView(frame:NSRect(x:16,y:64,width:368,height:276));scroll.hasVerticalScroller=true;scroll.drawsBackground=false
        let doc=FlippedChatView(frame:NSRect(x:0,y:0,width:368,height:276));doc.translatesAutoresizingMaskIntoConstraints=false
        stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=10;stack.translatesAutoresizingMaskIntoConstraints=false
        doc.addSubview(stack);scroll.documentView=doc
        NSLayoutConstraint.activate([doc.widthAnchor.constraint(equalTo:scroll.contentView.widthAnchor),stack.leadingAnchor.constraint(equalTo:doc.leadingAnchor,constant:4),stack.trailingAnchor.constraint(equalTo:doc.trailingAnchor,constant:-4),stack.topAnchor.constraint(equalTo:doc.topAnchor,constant:4),stack.bottomAnchor.constraint(equalTo:doc.bottomAnchor,constant:-4)])
        content.addSubview(scroll)
        let refresh=NSButton(title:"导入 JSON",target:self,action:#selector(importJSON));refresh.bezelStyle = .rounded;refresh.frame=NSRect(x:20,y:20,width:120,height:30);content.addSubview(refresh)
        let browser=NSButton(title:"Chrome 登录 / 导出",target:self,action:#selector(openPortal));browser.bezelStyle = .rounded;browser.frame=NSRect(x:150,y:20,width:230,height:30);content.addSubview(browser)
        let data=(try? Data(contentsOf:cacheURL)) ?? Bundle.main.url(forResource:"tongji-notices",withExtension:"json").flatMap{try? Data(contentsOf:$0)}
        if let d=data {snapshot=try? JSONDecoder().decode(TongjiSnapshot.self,from:d)}
        render()
    }
    func show() {
        let screen=(owner.screen ?? NSScreen.main)!.visibleFrame
        let x=min(max(owner.frame.midX-200,screen.minX+8),screen.maxX-408)
        let y=max(screen.minY+8,min(owner.frame.maxY-8,screen.maxY-428))
        panel.setFrameOrigin(NSPoint(x:x,y:y));panel.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    @objc func hide(){panel.orderOut(nil)}
    @objc func openPortal(){
        if let chrome=NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.google.Chrome") {
            NSWorkspace.shared.open([origin],withApplicationAt:chrome,configuration:NSWorkspace.OpenConfiguration())
        } else {NSWorkspace.shared.open(origin)}
    }
    @objc func importJSON(){
        let picker=NSOpenPanel();picker.title="导入同济news扩展导出的 JSON";picker.allowedContentTypes=[.json];picker.allowsMultipleSelection=false;picker.canChooseDirectories=false
        guard picker.runModal() == .OK,let url=picker.url else{return}
        do {
            let resource=try url.resourceValues(forKeys:[.fileSizeKey]);guard (resource.fileSize ?? 0)<=65536 else{throw NoticeImportError.invalid}
            let data=try Data(contentsOf:url);let imported=try TongjiImport.validate(data)
            try FileManager.default.createDirectory(at:cacheURL.deletingLastPathComponent(),withIntermediateDirectories:true)
            try JSONEncoder().encode(imported).write(to:cacheURL,options:.atomic)
            snapshot=imported;render();status.stringValue="已导入 \(imported.notices.count) 条 · \(imported.updatedAt)"
        } catch {status.stringValue="导入失败：请选扩展导出的有效 JSON（最多64 KB），原公告未更改"}
    }
    func render(){
        for v in stack.arrangedSubviews {stack.removeArrangedSubview(v);v.removeFromSuperview()}
        guard let snapshot=snapshot else {status.stringValue="尚无公告，请在 Chrome 导出后导入 JSON";return}
        status.stringValue="标题列表 · 更新于 \(snapshot.updatedAt) · 点击查看来源"
        let list=snapshot.notices.sorted{a,b in a.pinned != b.pinned ? !a.pinned : a.date>b.date}
        for (i,n) in list.enumerated(){
            let button=NSButton(title:"\(n.pinned ? "置顶 · " : "")\(n.date.prefix(10))\n\(n.title)",target:self,action:#selector(openItem(_:)))
            button.tag=i;button.isBordered=false;button.alignment = .left;button.font = .systemFont(ofSize:12)
            button.cell?.wraps=true;button.cell?.isScrollable=false;button.wantsLayer=true;button.layer?.cornerRadius=12;button.layer?.backgroundColor=NSColor.controlBackgroundColor.withAlphaComponent(0.6).cgColor
            button.translatesAutoresizingMaskIntoConstraints=false;stack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true;button.heightAnchor.constraint(equalToConstant:76).isActive=true
        }
    }
    @objc func openItem(_ sender:NSButton){openPortal()}
}

enum NoticeImportError:Error {case invalid}
struct TongjiExport:Decodable {let schemaVersion:Int;let source:String;let exportedAt:String;let notices:[TongjiNotice]}
enum TongjiImport {
    static func validate(_ data:Data)throws->TongjiSnapshot {
        guard data.count<=65536,let root=try JSONSerialization.jsonObject(with:data) as? [String:Any],Set(root.keys)==Set(["schemaVersion","source","exportedAt","notices"]),let rows=root["notices"] as? [[String:Any]],rows.allSatisfy({Set($0.keys)==Set(["title","date","pinned"])}) else{throw NoticeImportError.invalid}
        let input=try JSONDecoder().decode(TongjiExport.self,from:data)
        guard input.schemaVersion==1,input.source=="https://1.tongji.edu.cn/workbench",!input.notices.isEmpty,input.notices.count<=100 else{throw NoticeImportError.invalid}
        let iso=ISO8601DateFormatter();iso.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        guard let timestamp=iso.date(from:input.exportedAt),timestamp<=Date().addingTimeInterval(300) else{throw NoticeImportError.invalid}
        let calendar=DateFormatter();calendar.locale=Locale(identifier:"en_US_POSIX");calendar.dateFormat="yyyy-MM-dd";calendar.isLenient=false
        var seen=Set<String>();var notices=[TongjiNotice]()
        for n in input.notices {
            let title=n.title.trimmingCharacters(in:.whitespacesAndNewlines)
            guard (5...400).contains(title.count),!title.unicodeScalars.contains(where:{$0.value<32}),n.date.range(of:#"^20[0-9]{2}-[0-9]{2}-[0-9]{2}$"#,options:.regularExpression) != nil,let d=calendar.date(from:n.date),calendar.string(from:d)==n.date else{throw NoticeImportError.invalid}
            if seen.insert(title+"|"+n.date).inserted {notices.append(TongjiNotice(title:title,date:n.date,pinned:false))}
        }
        let display=DateFormatter();display.dateFormat="yyyy-MM-dd HH:mm";display.timeZone = .current
        return TongjiSnapshot(updatedAt:display.string(from:timestamp)+"（手动导出）",notices:notices)
    }
}
