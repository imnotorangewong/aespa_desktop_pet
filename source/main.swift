import AppKit

let counts = [6,8,8,4,5,8,6,6,6]
func lookIndex(dx: Double, dy: Double) -> Int? {
    if hypot(dx,dy) < 14 { return nil }
    // 0 = up, clockwise in screen coordinates.
    let angle = atan2(dx,dy)
    return (Int((angle / (2 * .pi) * 16).rounded()) + 16) % 16
}
final class PetView: NSView {
    var frames: [[NSImage]] = []
    var row = 0; var frameIndex = 0; var action = false
    var started = ProcessInfo.processInfo.systemUptime
    var timer: Timer?
    var downPoint = NSPoint.zero; var downOrigin = NSPoint.zero; var dragging = false
    var previousAction = -1
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    init(sheet: CGImage) {
        super.init(frame: NSRect(x:0,y:0,width:192,height:208))
        for r in 0..<11 {
            var a: [NSImage] = []
            for c in 0..<(r < 9 ? counts[r] : 8) {
                let crop = sheet.cropping(to: CGRect(x:c*192,y:r*208,width:192,height:208))!
                a.append(NSImage(cgImage:crop,size:NSSize(width:192,height:208)))
            }
            frames.append(a)
        }
        timer = Timer.scheduledTimer(withTimeInterval:1.0/30.0,repeats:true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!,forMode:.common)
    }
    @discardableResult func applySkin(_ skin:LoadedPetSkin)->Bool {
        guard skin.frames.map({$0.count})==PetSkinRegistry.rowCounts else{return false}
        frames=skin.frames;row=0;frameIndex=0;action=false;previousAction = -1;started=ProcessInfo.processInfo.systemUptime;needsDisplay=true;return true
    }
    required init?(coder:NSCoder) { fatalError() }
    func tick() {
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        if action {
            let i = Int(elapsed * 8)
            if i >= frames[row].count * 2 { action=false; started=ProcessInfo.processInfo.systemUptime; row=0; frameIndex=0 }
            else { frameIndex=i % frames[row].count }
        } else if let w=window {
            let p=w.convertPoint(fromScreen:NSEvent.mouseLocation)
            if bounds.contains(p), let i=lookIndex(dx:p.x-96,dy:p.y-78) {
                row=9+i/8; frameIndex=i%8
            } else {
                row=0; frameIndex=Int(elapsed*6)%counts[0]
            }
        }
        needsDisplay=true
    }
    override func draw(_ dirtyRect:NSRect) {
        NSColor.clear.setFill(); dirtyRect.fill(using:.copy)
        NSGraphicsContext.current?.imageInterpolation = .none
        frames[row][frameIndex].draw(in:bounds,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
    }
    override func mouseDown(with event:NSEvent) { downPoint=NSEvent.mouseLocation; downOrigin=window!.frame.origin; dragging=false }
    override func mouseDragged(with event:NSEvent) {
        let p=NSEvent.mouseLocation
        if hypot(p.x-downPoint.x,p.y-downPoint.y)>4 { dragging=true }
        if dragging { window?.setFrameOrigin(NSPoint(x:downOrigin.x+p.x-downPoint.x,y:downOrigin.y+p.y-downPoint.y)) }
    }
    override func mouseUp(with event:NSEvent) {
        if dragging { return }
        let choices=(1..<9).filter{$0 != previousAction}
        row=choices.randomElement()!; previousAction=row; frameIndex=0; action=true
        started=ProcessInfo.processInfo.systemUptime; needsDisplay=true
    }
    override func rightMouseDown(with event:NSEvent) {
        guard let delegate=NSApp.delegate as? AppDelegate else{return}
        NSMenu.popUpContextMenu(delegate.menuPreferences.menu(target:delegate, group:delegate.skins.current?.descriptor.group ?? .aespa),with:event,for:self)
    }
}
final class PetPanel:NSPanel {
    override var canBecomeKey:Bool { false }
    override var canBecomeMain:Bool { false }
}
final class AppDelegate:NSObject, NSApplicationDelegate {
    let skins=PetSkinStore()
    let menuPreferences=PetMenuPreferences()
    var settings:PetSettingsController?
    @objc func showSettings(){if settings == nil{settings=PetSettingsController(owner:panel,preferences:menuPreferences,skins:skins,onSkinChange:{[weak self] skin in
        guard let self=self,(self.panel.contentView as? PetView)?.applySkin(skin)==true else{return false}
        self.chat?.updateIdentity(skin.descriptor.title)
        self.gallery?.setGroup(skin.descriptor.group)
        return true
    })};settings?.show()}
    private var restarting=false
    @objc func restartPet() {
        guard !restarting else{return};restarting=true
        let alert=NSAlert();alert.messageText="重启桌宠？";alert.informativeText="当前内存聊天会清空。桌宠退出后，将自动打开同一位置的最新版。";alert.addButton(withTitle:"重启");alert.addButton(withTitle:"取消")
        guard alert.runModal() == .alertFirstButtonReturn else{restarting=false;return}
        do {try PetRestart.start();NSApp.terminate(nil)} catch {
            restarting=false;let failure=NSAlert();failure.messageText="暂时无法重启";failure.informativeText="未退出桌宠。请确认应用仍在原位置，再试一次。";failure.runModal()
        }
    }
    var panel:PetPanel!
    var gallery:GalleryController?
    @objc func showGallery(){gallery?.show()}
    var music:MusicCalendarController?
    @objc func showMusic(){music?.show()}
    var rank:AIRankController?
    @objc func showRank(){rank?.show()}
    var news:TongjiNewsController?
    @objc func showNews(){if news == nil {news=TongjiNewsController(owner:panel)};news?.show()}
    var chat:ChatController?
    @objc func showChat() {if chat == nil {chat=ChatController(owner:panel,personaName:skins.current?.descriptor.title ?? "Ning Ning")};chat?.show(above:panel)}
    func applicationDidFinishLaunching(_ notification:Notification) {
        guard let skin=skins.current else {
            let alert=NSAlert(); alert.messageText="动画素材缺失或损坏"; alert.runModal(); NSApp.terminate(nil); return
        }
        let screen=NSScreen.main!.visibleFrame
        panel=PetPanel(contentRect:NSRect(x:screen.maxX-240,y:screen.minY+40,width:192,height:208),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.isOpaque=false; panel.backgroundColor = .clear; panel.hasShadow=false
        panel.level = .floating; panel.hidesOnDeactivate=false
        panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
        panel.isMovableByWindowBackground=false; panel.acceptsMouseMovedEvents=true
        let pet=PetView(sheet:skin.sheet);pet.applySkin(skin);panel.contentView=pet; panel.orderFrontRegardless()
        rank=AIRankController(owner:panel);rank?.startUpdates()
        music=MusicCalendarController(owner:panel)
        if CommandLine.arguments.contains("--show-music-calendar") { music?.show() }
        gallery=GalleryController(owner:panel, group:skin.descriptor.group);gallery?.start()
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool { panel?.orderFrontRegardless(); return false }
}
if CommandLine.arguments.contains("--gallery-global-test") || CommandLine.arguments.contains("--gallery-global-image-test") {
    let html=try String(contentsOfFile:"/tmp/aespa-global.html",encoding:.utf8),root=try String(contentsOfFile:"/tmp/aespa-global.js",encoding:.utf8),view=try String(contentsOfFile:"/tmp/aespa-lemonade.js",encoding:.utf8)
    _ = try GalleryGlobalParser.rootScript(html);_ = try GalleryGlobalParser.viewScript(root);let items=try GalleryGlobalParser.items(view)
    print("Official global declarations:",items.count,"candidates; Ningning:",items.filter{$0.ningning}.count,"dates absent:",items.allSatisfy{$0.date==nil})
    if CommandLine.arguments.contains("--gallery-global-image-test") {
        let url=GalleryRules.safeURL(items.last!.imageURL!,image:true)!;var done=false,ok=false
        let fetch=GalleryFetch(url:url,cap:8_000_000,image:true){result in if let data=try? result.get(){ok=GalleryQueue.imageValid(data);print("Official global image decode:",ok,"bytes:",data.count)}else{print("Official global image fetch failed")};done=true}
        let until=Date().addingTimeInterval(35);while !done && Date()<until{RunLoop.main.run(until:Date().addingTimeInterval(0.1))};if !done{fetch.cancel()};exit(ok ? 0:1)
    }
} else if CommandLine.arguments.contains("--gallery-image-test") {
    let items=try GalleryFeedParser.parse(Data(contentsOf:URL(fileURLWithPath:"/tmp/aespa-feed.xml")))
    let url=GalleryRules.safeURL(items.compactMap{$0.imageURL}.first!,image:true)!
    var done=false,ok=false
    let fetch=GalleryFetch(url:url,cap:8_000_000,image:true){result in if let data=try? result.get(){ok=GalleryQueue.imageValid(data);print("Official image decode:",ok,"bytes:",data.count)}else{print("Official image fetch failed")};done=true}
    let until=Date().addingTimeInterval(35);while !done && Date()<until{RunLoop.main.run(until:Date().addingTimeInterval(0.1))};if !done{fetch.cancel()};exit(ok ? 0:1)
} else if CommandLine.arguments.contains("--gallery-parse-test") {
    let data=try Data(contentsOf:URL(fileURLWithPath:"/tmp/aespa-feed.xml"));let items=try GalleryFeedParser.parse(data);print("Official cached feed parse:",items.count,"items; images:",items.filter{$0.imageURL != nil}.count,"Ningning-text:",items.filter{$0.ningning}.count)
} else if let index = CommandLine.arguments.firstIndex(of: "--music-catalog-play-test"),
          CommandLine.arguments.indices.contains(index + 1) {
    exit(musicCatalogPlayTest(day: CommandLine.arguments[index + 1]) ? 0 : 1)
} else if CommandLine.arguments.contains("--music-probe") {
    musicReadOnlyProbe(repair: CommandLine.arguments.contains("--repair-covers"))
} else if CommandLine.arguments.contains("--arena-test") {
    let store=ArenaRankStore();var done=false;store.onChange={if store.status.contains("成功") || store.status.contains("失败"){done=true}};store.updateOnce()
    let until=Date().addingTimeInterval(50);while !done && Date()<until{RunLoop.main.run(until:Date().addingTimeInterval(0.1))}
    print("Arena:",store.status,"rows:",store.snapshot?.rows.count ?? 0,"published:",store.snapshot?.release ?? "none");exit(done && store.status.contains("成功") ? 0:1)
} else if CommandLine.arguments.contains("--store-aa-key") {
    let data=FileHandle.standardInput.readDataToEndOfFile();let key=String(data:data,encoding:.utf8)?.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""
    guard !key.isEmpty,key.count<=1024,!key.unicodeScalars.contains(where:{$0.value<33}) else{exit(2)}
    let status=AAKeyStore.save(key);print(status==0 ? "AA Local credential saved" : "AA local credential save failed");exit(status==0 ? 0:1)
} else if CommandLine.arguments.contains("--rank-live-test") {
    let store=AIRankStore();var done=false
    store.onChange={if store.status.contains("成功") || store.status.contains("失败"){done=true}}
    store.updateOnce();let until=Date().addingTimeInterval(110);while !done && Date()<until{RunLoop.main.run(until:Date().addingTimeInterval(0.1))}
    print("LiveBench:",store.status,"rows:",store.snapshot?.rows.count ?? 0,"release:",store.snapshot?.release ?? "none");exit(done && store.status.contains("成功") ? 0:1)
} else if CommandLine.arguments.contains("--aa-test") {
    let store=AARankStore();var done=false
    store.onChange={if store.status.contains("成功") || store.status.contains("失败") || store.status.contains("未配置"){done=true}}
    store.updateOnce();let until=Date().addingTimeInterval(110);while !done && Date()<until{RunLoop.main.run(until:Date().addingTimeInterval(0.1))}
    print("AA:",store.status,"rows:",store.snapshot?.rows.count ?? 0,"index version:",store.snapshot?.release ?? "none");exit(done && store.status.contains("成功") ? 0:1)
} else if CommandLine.arguments.contains("--key-status") {
    let available=KeyStore.get() != nil;print(available ? "Local credential available without prompt" : "Local credential unavailable: \(KeyStore.lastStatus)");exit(0)
} else if CommandLine.arguments.contains("--store-key") {
    let data=FileHandle.standardInput.readDataToEndOfFile();let key=String(data:data,encoding:.utf8)!.trimmingCharacters(in:.whitespacesAndNewlines)
    guard !key.isEmpty else {exit(2)}
    let status=KeyStore.save(key);print(status==0 ? "Local credential saved" : "Local credential error: \(status)");exit(status==0 ? 0:1)
} else if CommandLine.arguments.contains("--api-test") {
    let client=DeepSeekClient();var done=false;var ok=false
    client.send([ChatMessage(role:"user",content:"只回复：连接成功")]) {r in DispatchQueue.main.async {switch r {case .success(let text):print("API OK: \(text)");ok=true;case .failure(let e):print("API failed: \(e.localizedDescription)")};done=true}}
    let limit=Date().addingTimeInterval(125);while !done && Date()<limit {RunLoop.main.run(until:Date().addingTimeInterval(0.1))};exit(ok ? 0:1)
} else if CommandLine.arguments.contains("--self-test") {
    restartSelfTest()
    panelBackgroundDragSelfTest()
    musicSelfTest()
    gallerySelfTest()
    precondition(lookIndex(dx:0,dy:50)==0)
    precondition(lookIndex(dx:50,dy:0)==4)
    precondition(lookIndex(dx:0,dy:-50)==8)
    precondition(lookIndex(dx:-50,dy:0)==12)
    precondition(lookIndex(dx:1,dy:1)==nil)
    precondition(counts.reduce(0,+)==57)
    guard let url=Bundle.main.url(forResource:"spritesheet-clean",withExtension:"png"),let im=NSImage(contentsOf:url),let cg=im.cgImage(forProposedRect:nil,context:nil,hints:nil) else { fatalError("missing sheet") }
    let view=PetView(sheet:cg)
    precondition(view.frames.count==11 && view.frames[10].count==8)
    for row in view.frames { for image in row { precondition(image.size.width==192 && image.size.height==208) } }
    let app=NSApplication.shared
    app.setActivationPolicy(.accessory)
    petSkinSelfTest()
    petSettingsSelfTest()
    let owner=PetPanel(contentRect:NSRect(x:0,y:0,width:192,height:208),styleMask:[.borderless],backing:.buffered,defer:false)
    let chat=ChatController(owner:owner)
    precondition(chat.messages.arrangedSubviews.count==1)
    precondition(ChatController.welcomeText.hasPrefix("你可以问我这些哟～"))
    precondition(ChatController.welcomeText.components(separatedBy:"•").count==4)
    chat.ensureWelcome();chat.closeChat();chat.ensureWelcome()
    precondition(chat.messages.arrangedSubviews.count==1 && chat.history.isEmpty)
    chat.append("你","测试一句短消息")
    chat.append("略略",String(repeating:"这是一段用于检查气泡自动换行和布局的测试文字。",count:12))
    chat.panel.contentView?.layoutSubtreeIfNeeded()
    precondition(chat.messages.arrangedSubviews.count==3)
    let historyBefore=[ChatMessage(role:"user",content:"保留这句话"),ChatMessage(role:"assistant",content:"原正文保留略略字样不改")];chat.history=historyBefore
    let unchangedRows=chat.messages.arrangedSubviews;let requestBefore=chat.requestID;chat.busy=true;chat.input.stringValue="未发送草稿"
    for name in PetSkinRegistry.entries.map({ $0.title }) {
        chat.updateIdentity(name)
        precondition(chat.panel.title==name+"聊天" && chat.identityTitle.stringValue==name && chat.assistantDisplayedNames.allSatisfy{$0==name})
        precondition(chat.messages.arrangedSubviews.elementsEqual(unchangedRows,by:{$0 === $1}) && chat.history.map{$0.content}==historyBefore.map{$0.content})
        precondition(chat.requestID==requestBefore && chat.busy && chat.input.stringValue=="未发送草稿")
        precondition(ChatConfig.load().prompt(for:name).contains("当前桌宠角色昵称是 "+name))
        precondition(ChatConfig.load().prompt(for:name).hasPrefix(ChatConfig.load().systemPrompt.replacingOccurrences(of:"你是桌宠「略略」",with:"你是桌宠「"+name+"」")))
    }
    chat.append(chat.personaName,"模拟切换期间到达的回复");precondition(chat.assistantDisplayedNames.last==PetSkinRegistry.entries.last?.title)
    chat.busy=false
    print("PASS: all registered skin chat identities, historical bubble labels, unchanged history/draft/request ID/busy state and current-name late reply")
    for row in chat.messages.arrangedSubviews {precondition(row.frame.width>0 && row.frame.height>0)}
    precondition(!chat.status.stringValue.contains("DeepSeek"))
    precondition(!ChatConfig.load().systemPrompt.isEmpty)
    let news=TongjiNewsController(owner:owner);precondition(news.snapshot?.notices.count==0);precondition(news.stack.arrangedSubviews.count==0)
    let rank=AIRankController(owner:owner);precondition(rank.tabs.segmentCount==3);precondition(rank.table.tableColumns.count==8)
    rank.tabs.selectedSegment=1;rank.render();precondition(rank.table.tableColumns.count==3)
    rank.tabs.selectedSegment=0;rank.render();precondition(rank.table.tableColumns.count==6)
    print("PASS: sprites, chat, news, three rank tabs and table schemas")
} else {
    let app=NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate=AppDelegate(); app.delegate=delegate; app.run()
}
