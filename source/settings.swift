import AppKit

// Derive the menu icon only from the existing first idle frame; retain original colors/alpha.
enum PetMenuIcon {
    static let settings:NSImage? = {
        guard let icon=NSImage(systemSymbolName:"gearshape",accessibilityDescription:"设置")?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize:14,weight:.regular)) else{return nil}
        icon.size=NSSize(width:16,height:16);icon.isTemplate=true;return icon
    }()
    static var restart:NSImage? {makeRestart(sheet:(NSApp.delegate as? AppDelegate)?.skins.current?.sheet)}
    static func makeRestart(sheet selected:CGImage?)->NSImage? {
        guard let url=Bundle.main.url(forResource:"spritesheet-clean",withExtension:"png"),let source=NSImage(contentsOf:url),let fallback=source.cgImage(forProposedRect:nil,context:nil,hints:nil),let frame=(selected ?? fallback).cropping(to:CGRect(x:0,y:0,width:192,height:208)) else{return nil}
        let bitmap=NSBitmapImageRep(cgImage:frame);var minX=192,minY=208,maxX = -1,maxY = -1
        for y in 0..<208 {for x in 0..<192 {if (bitmap.colorAt(x:x,y:y)?.alphaComponent ?? 0)>0.01 {minX=min(minX,x);minY=min(minY,y);maxX=max(maxX,x);maxY=max(maxY,y)}}}
        guard maxX>=minX,maxY>=minY,let cropped=frame.cropping(to:CGRect(x:minX,y:minY,width:maxX-minX+1,height:maxY-minY+1)),let context=CGContext(data:nil,width:32,height:32,bitsPerComponent:8,bytesPerRow:128,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{return nil}
        let scale=28.0/Double(max(cropped.width,cropped.height));let w=Double(cropped.width)*scale,h=Double(cropped.height)*scale
        context.interpolationQuality = .high;context.draw(cropped,in:CGRect(x:(32-w)/2,y:(32-h)/2,width:w,height:h))
        guard let result=context.makeImage() else{return nil};let icon=NSImage(cgImage:result,size:NSSize(width:16,height:16));icon.isTemplate=false;return icon
    }
}

enum PetFeature:String,CaseIterable {
    case chat,news,rank,music,gallery
    func title(for group: PetGroup) -> String {switch self{case .chat:return "聊天";case .news:return "同济news";case .rank:return "AI rank";case .music:return "Music Calendar";case .gallery:return group.galleryTitle}}
    var action:Selector {switch self{case .chat:return #selector(AppDelegate.showChat);case .news:return #selector(AppDelegate.showNews);case .rank:return #selector(AppDelegate.showRank);case .music:return #selector(AppDelegate.showMusic);case .gallery:return #selector(AppDelegate.showGallery)}}
}
struct PetMenuConfig:Codable,Equatable {
    var order:[String]=PetFeature.allCases.map{$0.rawValue}
    var hidden:[String]=[]
    func normalized(registryIDs:[String]=PetFeature.allCases.map{$0.rawValue})->PetMenuConfig {
        let known=Set(registryIDs);var seen=Set<String>()
        let complete=(order+registryIDs).filter{known.contains($0) && seen.insert($0).inserted}
        return PetMenuConfig(order:complete,hidden:registryIDs.filter{hidden.contains($0)})
    }
}
final class PetMenuPreferences {
    static let key="pet.menu.preferences.v1"
    private let defaults:UserDefaults
    private(set) var config=PetMenuConfig()
    init(defaults:UserDefaults = .standard){self.defaults=defaults;if let data=defaults.data(forKey:Self.key),data.count<=4096,let saved=try? JSONDecoder().decode(PetMenuConfig.self,from:data){config=saved.normalized()}}
    private func save(){config=config.normalized();if let data=try? JSONEncoder().encode(config){defaults.set(data,forKey:Self.key)}}
    func setVisible(_ visible:Bool,feature:String){guard PetFeature(rawValue:feature) != nil else{return};config.hidden.removeAll{$0==feature};if !visible{config.hidden.append(feature)};save()}
    func move(_ feature:String,by offset:Int){guard abs(offset)==1,let index=config.order.firstIndex(of:feature),config.order.indices.contains(index+offset) else{return};config.order.swapAt(index,index+offset);save()}
    func menu(target:AnyObject?, group: PetGroup = .aespa)->NSMenu {
        let menu=NSMenu()
        for id in config.order where !config.hidden.contains(id) {
            guard let feature = PetFeature(rawValue: id) else { continue }
            let item = NSMenuItem(title: feature.title(for: group), action: feature.action, keyEquivalent: "")
            if feature == .gallery, group == .ive {
                let font = NSFont(name: "SnellRoundhand-Bold", size: 16) ?? .menuFont(ofSize: 16)
                item.attributedTitle = NSAttributedString(string: item.title, attributes: [.font: font])
            }
            item.target = target
            menu.addItem(item)
        }
        if !menu.items.isEmpty{menu.addItem(.separator())}
        let settings=NSMenuItem(title:"设置",action:#selector(AppDelegate.showSettings),keyEquivalent:"");settings.target=target;settings.image=PetMenuIcon.settings;menu.addItem(settings)
        let quit=NSMenuItem(title:"退出桌宠",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"");quit.target=NSApp;menu.addItem(quit)
        let restart=NSMenuItem(title:"重启桌宠",action:#selector(AppDelegate.restartPet),keyEquivalent:"");restart.target=target;restart.image=PetMenuIcon.restart;restart.toolTip="清空本次聊天并重新打开此位置的最新版";menu.addItem(restart)
        return menu
    }
}
enum ChatKeyConfiguration {
    static func field()->NSSecureTextField {
        let field=NSSecureTextField(frame:NSRect(x:0,y:0,width:350,height:28))
        field.stringValue="";field.placeholderString="输入你自己的 DeepSeek API Key";field.setAccessibilityLabel("聊天 API Key，安全输入")
        return field
    }
    static func save(_ raw:String,using writer:(String)->OSStatus=KeyStore.save)->OSStatus {
        let value=raw.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !value.isEmpty,value.utf8.count<=1024,!value.unicodeScalars.contains(where:{$0.value<33}) else{return errSecParam}
        return writer(value)
    }
}
func chatKeyConfigurationSelfTest(){
    let field=ChatKeyConfiguration.field();precondition(field.stringValue.isEmpty)
    var writes=[String]();let writer:(String)->OSStatus={writes.append($0);return errSecSuccess}
    precondition(ChatKeyConfiguration.save("",using:writer)==errSecParam)
    precondition(ChatKeyConfiguration.save("bad key",using:writer)==errSecParam)
    precondition(ChatKeyConfiguration.save(String(repeating:"x",count:1025),using:writer)==errSecParam && writes.isEmpty)
    precondition(ChatKeyConfiguration.save("  synthetic-test-value\n",using:writer)==errSecSuccess && writes==["synthetic-test-value"])
    precondition(ChatKeyConfiguration.save("synthetic-value",using:{_ in errSecIO})==errSecIO)
    precondition(ChatKeyConfiguration.field().stringValue.isEmpty)
    print("PASS: manual secure key field empty/reopened, validation, injected save success/failure; no real key read or API request")
}
final class PetSettingsController:NSObject {
    private var configuringChatKey=false
    @objc func configureChatKey(){
        guard !configuringChatKey else{return};configuringChatKey=true;defer{configuringChatKey=false}
        let field=ChatKeyConfiguration.field()
        let alert=NSAlert();alert.messageText="配置聊天 API Key"
        alert.informativeText="输入你自己的 DeepSeek API Key。仅保存到本机权限 600 的明文文件（目录 700），不使用钥匙串；同一用户下的其他程序仍可能读取。聊天内容会发送到 DeepSeek，可能产生服务费用。此处不发送测试请求。"
        alert.accessoryView=field;alert.addButton(withTitle:"保存");alert.addButton(withTitle:"取消");alert.window.initialFirstResponder=field
        guard alert.runModal() == .alertFirstButtonReturn else{field.stringValue="";return}
        let result=ChatKeyConfiguration.save(field.stringValue);field.stringValue=""
        let notice=NSAlert();notice.messageText=result==errSecSuccess ? "聊天密钥已保存":"未保存聊天密钥"
        notice.informativeText=result==errSecSuccess ? "后续聊天会自动读取，无需重启。密钥有效性和额度将在实际发送时由服务验证。":"请检查输入是否为空、包含空格，或本机私有目录权限是否正常。已有密钥保持不变。"
        notice.runModal()
    }


    let groupPicker = NSPopUpButton()
    private var browsingGroup: PetGroup
    let skinPicker=NSPopUpButton();let skins:PetSkinStore;let onSkinChange:(LoadedPetSkin)->Bool
    let panel:ChatPanel;let owner:NSWindow;let preferences:PetMenuPreferences
    let rows=NSView(frame:NSRect(x:20,y:72,width:390,height:250))
    init(owner:NSWindow,preferences:PetMenuPreferences,skins:PetSkinStore=PetSkinStore(),onSkinChange:@escaping(LoadedPetSkin)->Bool={_ in false}){
        browsingGroup = skins.current?.descriptor.group ?? .aespa
        self.skins=skins;self.onSkinChange=onSkinChange;self.owner=owner;self.preferences=preferences;panel=ChatPanel(contentRect:NSRect(x:0,y:0,width:430,height:410),styleMask:[.borderless],backing:.buffered,defer:false);super.init()
        panel.title="桌宠设置";panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=true;panel.level = .floating;panel.hidesOnDeactivate=false;panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
        let content=DragBackgroundView(frame:NSRect(x:0,y:0,width:430,height:410))
        if #available(macOS 26,*){let glass=NSGlassEffectView(frame:content.bounds);glass.cornerRadius=26;glass.contentView=content;panel.contentView=glass}else{let glass=NSVisualEffectView(frame:content.bounds);glass.material = .popover;glass.state = .active;glass.addSubview(content);panel.contentView=glass}
        let title=NSTextField(labelWithString:"设置");title.font = .systemFont(ofSize:20,weight:.semibold);title.frame=NSRect(x:24,y:360,width:250,height:30);content.addSubview(title)
        let close=NSButton(title:"×",target:self,action:#selector(hide));close.frame=NSRect(x:378,y:360,width:28,height:28);close.setAccessibilityLabel("关闭设置");content.addSubview(close)
        let configureChat=NSButton(title:"配置聊天 API Key",target:self,action:#selector(configureChatKey));configureChat.frame=NSRect(x:24,y:326,width:210,height:28);content.addSubview(configureChat)
        let scroll=NSScrollView(frame:rows.frame);scroll.hasVerticalScroller=true;scroll.drawsBackground=false;rows.setFrameOrigin(.zero);scroll.documentView=rows;content.addSubview(scroll)
        let groupLabel = NSTextField(labelWithString:"韩团")
        groupLabel.frame = NSRect(x:24,y:29,width:38,height:22)
        content.addSubview(groupLabel)
        groupPicker.frame = NSRect(x:63,y:24,width:102,height:30)
        groupPicker.setAccessibilityLabel("韩团")
        groupPicker.target = self
        groupPicker.action = #selector(changeGroup)
        content.addSubview(groupPicker)
        let skinLabel = NSTextField(labelWithString:"皮肤")
        skinLabel.frame = NSRect(x:182,y:29,width:38,height:22)
        content.addSubview(skinLabel)
        skinPicker.frame = NSRect(x:220,y:24,width:186,height:30)
        skinPicker.setAccessibilityLabel("皮肤")
        skinPicker.target = self
        skinPicker.action = #selector(changeSkin)
        content.addSubview(skinPicker)
        render()
    }

    private func renderPickers() {
        let groups = PetGroup.allCases.filter { group in skins.available.contains { $0.descriptor.group == group } }
        if !groups.contains(browsingGroup), let first = groups.first { browsingGroup = first }
        groupPicker.removeAllItems()
        groupPicker.addItems(withTitles:groups.map { $0.rawValue })
        groupPicker.selectItem(withTitle:browsingGroup.rawValue)
        groupPicker.isEnabled = !groups.isEmpty

        let members = skins.available.filter { $0.descriptor.group == browsingGroup }
        skinPicker.removeAllItems()
        if !members.contains(where:{ $0.descriptor.id == skins.selectedID }) {
            skinPicker.addItem(withTitle:"选择皮肤…")
            skinPicker.lastItem?.isEnabled = false
        }
        for skin in members {
            skinPicker.addItem(withTitle:skin.descriptor.title)
            skinPicker.lastItem?.representedObject = skin.descriptor.id
            if skin.descriptor.id == skins.selectedID { skinPicker.select(skinPicker.lastItem) }
        }
        skinPicker.isEnabled = !members.isEmpty
    }

    @objc func changeGroup() {
        guard let title = groupPicker.titleOfSelectedItem, let group = PetGroup(rawValue:title) else { return }
        browsingGroup = group
        renderPickers()
    }

    func render(){renderPickers();rows.subviews.forEach{$0.removeFromSuperview()};rows.setFrameSize(NSSize(width:390,height:max(250,preferences.config.order.count*48)));for (index,id) in preferences.config.order.enumerated(){guard let feature=PetFeature(rawValue:id) else{continue};let y=rows.bounds.height-CGFloat(index+1)*48
        let title = feature.title(for: skins.current?.descriptor.group ?? .aespa)
        let toggle=NSButton(checkboxWithTitle:title,target:self,action:#selector(toggleFeature(_:)));toggle.frame=NSRect(x:4,y:y+6,width:260,height:30);toggle.tag=index;toggle.state=preferences.config.hidden.contains(id) ? .off:.on;rows.addSubview(toggle)
        for (delta,x,label) in [(-1,CGFloat(280),"↑"),(1,CGFloat(332),"↓")]{let button=NSButton(title:label,target:self,action:delta<0 ? #selector(moveUp(_:)):#selector(moveDown(_:)));button.frame=NSRect(x:x,y:y+6,width:44,height:30);button.tag=index;button.isEnabled=preferences.config.order.indices.contains(index+delta);button.setAccessibilityLabel("\(title)\(delta<0 ? "上移":"下移")");rows.addSubview(button)}
    }}
    @objc func changeSkin(){guard let id = skinPicker.selectedItem?.representedObject as? String else{return};if !skins.select(id,apply:onSkinChange){let alert=NSAlert();alert.messageText="此皮肤暂时无法应用";alert.informativeText="保留当前皮肤，请检查素材是否完整。";alert.runModal();browsingGroup = skins.current?.descriptor.group ?? .aespa};render()}
    @objc func toggleFeature(_ sender:NSButton){guard preferences.config.order.indices.contains(sender.tag) else{return};preferences.setVisible(sender.state == .on,feature:preferences.config.order[sender.tag]);render()}
    private func move(_ sender:NSButton,_ delta:Int){guard preferences.config.order.indices.contains(sender.tag) else{return};preferences.move(preferences.config.order[sender.tag],by:delta);render()}
    @objc func moveUp(_ sender:NSButton){move(sender,-1)}
    @objc func moveDown(_ sender:NSButton){move(sender,1)}
    @objc func hide(){panel.orderOut(nil)}
    func show(){browsingGroup = skins.current?.descriptor.group ?? .aespa;let s=(owner.screen ?? NSScreen.main)!.visibleFrame;panel.setFrameOrigin(NSPoint(x:max(s.minX,min(owner.frame.midX-215,s.maxX-430)),y:max(s.minY,min(owner.frame.maxY-8,s.maxY-410))));render();panel.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)}
}
func petSettingsSelfTest(){
    chatKeyConfigurationSelfTest()
    precondition(PetMenuIcon.settings != nil && PetMenuIcon.settings!.size==NSSize(width:16,height:16) && PetMenuIcon.settings!.isTemplate)
    let suite="pet-menu-test-"+UUID().uuidString;let defaults=UserDefaults(suiteName:suite)!;defer{defaults.removePersistentDomain(forName:suite)}
    defaults.set(Data("invalid".utf8),forKey:PetMenuPreferences.key);precondition(PetMenuPreferences(defaults:defaults).config==PetMenuConfig())
    defaults.set(try! JSONEncoder().encode(PetMenuConfig(order:["gallery","bogus","gallery"],hidden:["chat","bogus","chat"])),forKey:PetMenuPreferences.key)
    let old=PetMenuConfig(order:["gallery","chat","gallery","retired"],hidden:["chat","retired"])
    let migrated=old.normalized(registryIDs:PetFeature.allCases.map{$0.rawValue}+["futureFeature"])
    precondition(migrated.order==["gallery","chat","news","rank","music","futureFeature"] && migrated.hidden==["chat"])
    precondition(migrated.normalized(registryIDs:PetFeature.allCases.map{$0.rawValue}+["futureFeature"])==migrated)
    let p=PetMenuPreferences(defaults:defaults);precondition(p.config.order==["gallery","chat","news","rank","music"] && p.config.hidden==["chat"])
    p.move("gallery",by:1);p.setVisible(true,feature:"chat");p.setVisible(false,feature:"music")
    precondition(PetMenuPreferences(defaults:defaults).config==p.config)
    let before=p.config;p.move("chat",by:-1);p.move("music",by:1);p.move("bogus",by:1);precondition(p.config==before)
    let menu=p.menu(target:nil)
    let icon=menu.items.last!.image!;precondition(icon.size==NSSize(width:16,height:16) && !icon.isTemplate)
    let preview=NSBitmapImageRep(data:icon.tiffRepresentation!)!;precondition(preview.pixelsWide==32 && preview.pixelsHigh==32)
    precondition((preview.colorAt(x:0,y:0)?.alphaComponent ?? 1)==0)
    try! preview.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"/tmp/pet-restart-menu-icon.png"))
    print("PASS: restart icon first idle frame, 16pt/32px, original color and transparent corner")
    precondition(menu.items.filter{!$0.isSeparatorItem}.map{$0.title}==["聊天","Aespa","同济news","AI rank","设置","退出桌宠","重启桌宠"])
    let iveItem = p.menu(target:nil, group:.ive).items[1]
    precondition(iveItem.title == "IVE" && iveItem.attributedTitle?.string == "IVE" && iveItem.action == #selector(AppDelegate.showGallery))
    for f in PetFeature.allCases{p.setVisible(false,feature:f.rawValue)}
    precondition(p.menu(target:nil).items.map{$0.title}==["设置","退出桌宠","重启桌宠"])
    let owner=NSWindow(contentRect:NSRect(x:0,y:0,width:100,height:100),styleMask:[.borderless],backing:.buffered,defer:false)
    let settings=PetSettingsController(owner:owner,preferences:p);precondition(settings.rows.subviews.count==15)
    let toggle=settings.rows.subviews.compactMap{$0 as? NSButton}.first!;toggle.state = .on;settings.toggleFeature(toggle);precondition(!p.config.hidden.contains(p.config.order[0]));settings.hide();settings.render();precondition(settings.rows.subviews.count==15)
    print("PASS: menu preferences corrupt fallback, normalized complete order, reload/new-feature migration, boundaries, all-hidden fixed actions, settings controls; no service lifecycle calls")
}
