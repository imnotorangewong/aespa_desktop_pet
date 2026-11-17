import AppKit
import Security
import LocalAuthentication

struct ChatMessage: Codable { let role:String; let content:String }
struct ChatConfig: Codable {
    var model = "deepseek-flash"
    var systemPrompt = "" // Reserved for the user's later personality definition.
    func prompt(for name:String)->String {
        let safe=PetSkinRegistry.entries.contains{$0.title==name} ? name:"Ning Ning"
        return systemPrompt.replacingOccurrences(of:"你是桌宠「略略」",with:"你是桌宠「"+safe+"」")+"\n当前桌宠角色昵称是 "+safe+"，这是虚构桌宠身份，不代表真人本人或官方代言。仅更新称呼，以上对话范围和语气规则保持不变。"
    }
    static func load() -> ChatConfig {
        guard let url=Bundle.main.url(forResource:"chat-config",withExtension:"json"), let d=try? Data(contentsOf:url), let c=try? JSONDecoder().decode(ChatConfig.self,from:d) else { return ChatConfig() }
        return c
    }
}
enum KeyStore {
    private static var cachedKey:String?
    private(set) static var lastStatus:OSStatus=errSecSuccess
    static let directory=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/imnotorange-pet/private",isDirectory:true)
    static var file:URL {directory.appendingPathComponent("chat-api-key")}
    static var accessMessage:String {"本机聊天凭据缺失或权限不正确，请右键桌宠 → 设置 → 配置聊天 API Key。"}
    static func get() -> String? {
        if let key=cachedKey{return key}
        let fd=open(file.path,O_RDONLY|O_NOFOLLOW)
        guard fd>=0 else {lastStatus=errSecItemNotFound;return nil}
        defer{close(fd)}
        var st=stat()
        guard fstat(fd,&st)==0,st.st_uid==getuid(),(st.st_mode & 0o777)==0o600,(st.st_mode & S_IFMT)==S_IFREG,st.st_size>0,st.st_size<=1024 else {lastStatus=errSecAuthFailed;return nil}
        var bytes=[UInt8](repeating:0,count:Int(st.st_size))
        guard read(fd,&bytes,bytes.count)==bytes.count,let key=String(bytes:bytes,encoding:.utf8),!key.isEmpty else {lastStatus=errSecDecode;return nil}
        cachedKey=key;lastStatus=errSecSuccess;return key
    }
    static func save(_ value:String) -> OSStatus {
        guard !value.isEmpty,value.utf8.count<=1024,!value.unicodeScalars.contains(where:{$0.value<33}) else{return errSecParam}
        do {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            let attrs=try FileManager.default.attributesOfItem(atPath:directory.path)
            guard attrs[.type] as? FileAttributeType == .typeDirectory,attrs[.ownerAccountID] as? UInt32 == getuid() else{return errSecAuthFailed}
            try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:directory.path)
            let temporary=directory.appendingPathComponent(UUID().uuidString)
            let fd=open(temporary.path,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0o600)
            guard fd>=0 else{return errSecIO}
            let data=Data(value.utf8);let count=data.withUnsafeBytes{write(fd,$0.baseAddress,data.count)};close(fd)
            defer{try? FileManager.default.removeItem(at:temporary)}
            guard count==data.count,rename(temporary.path,file.path)==0 else{return errSecIO}
            cachedKey=value;return errSecSuccess
        } catch {return errSecIO}
    }
}
final class NoRedirect:NSObject,URLSessionTaskDelegate {
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void){completionHandler(nil)}
}
final class DeepSeekClient {
    private let delegate=NoRedirect()
    private lazy var session:URLSession = {
        let c=URLSessionConfiguration.ephemeral;c.timeoutIntervalForRequest=90;c.timeoutIntervalForResource=120
        c.urlCache=nil;c.httpCookieStorage=nil
        return URLSession(configuration:c,delegate:delegate,delegateQueue:nil)
    }()
    @discardableResult func send(_ messages:[ChatMessage],persona:String="Ning Ning",completion:@escaping(Result<String,Error>)->Void)->URLSessionDataTask? {
        func error(_ text:String)->NSError {NSError(domain:"PurplePet",code:1,userInfo:[NSLocalizedDescriptionKey:text])}
        guard let key=KeyStore.get(),!key.isEmpty else {completion(.failure(error(KeyStore.accessMessage)));return nil}
        let config=ChatConfig.load()
        var chat=Array(messages.suffix(20))
        chat.insert(ChatMessage(role:"system",content:config.prompt(for:persona)),at:0)
        let body:[String:Any]=["model":config.model,"messages":chat.map{["role":$0.role,"content":$0.content]},"stream":false,"max_tokens":1024,"thinking":["type":"disabled"]]
        var request=URLRequest(url:URL(string:"https://api.deepseek.com/chat/completions")!)
        request.httpMethod="POST";request.setValue("Bearer \(key)",forHTTPHeaderField:"Authorization");request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.httpBody=try? JSONSerialization.data(withJSONObject:body)
        let task=session.dataTask(with:request){data,response,networkError in
            if let e=networkError {completion(.failure(e));return}
            guard let http=response as? HTTPURLResponse else {completion(.failure(error("服务器未返回有效响应。")));return}
            guard http.statusCode==200 else {
                let hint:[Int:String]=[401:"密钥无效或已失效。",402:"DeepSeek 账户余额不足。",429:"请求过于频繁，请稍后再试。",400:"请求配置不受支持。",503:"DeepSeek 暂时繁忙。"]
                completion(.failure(error(hint[http.statusCode] ?? "请求失败（HTTP \(http.statusCode)）。")));return
            }
            guard let data=data,let json=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],let choices=json["choices"] as? [[String:Any]],let message=choices.first?["message"] as? [String:Any],let content=message["content"] as? String,!content.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {completion(.failure(error("返回内容为空，请重试。")));return}
            completion(.success(content))
        };task.resume();return task
    }
}
final class ChatPanel:NSPanel {
    override var canBecomeKey:Bool{true}
    override var canBecomeMain:Bool{false}
}
// Only a direct hit on genuinely empty panel background may start a window drag.
// Descendant controls keep all mouse, text-selection, scrolling and date-click events.
final class DragBackgroundView:NSView {
    override var mouseDownCanMoveWindow:Bool { false }
    func permitsBackgroundDrag(at pointInSuperview:NSPoint)->Bool { hitTest(pointInSuperview) === self }
    override func mouseDown(with event:NSEvent) {
        guard let window=window,event.type == .leftMouseDown,
              let parent=superview,
              permitsBackgroundDrag(at:parent.convert(event.locationInWindow,from:nil)) else { return }
        window.performDrag(with:event)
    }
}
func panelBackgroundDragSelfTest() {
    let root=DragBackgroundView(frame:NSRect(x:10,y:20,width:400,height:300))
    precondition(root.permitsBackgroundDrag(at:NSPoint(x:390,y:290)))
    precondition(!root.permitsBackgroundDrag(at:NSPoint(x:0,y:0)))
    let input=NSTextField(frame:NSRect(x:20,y:20,width:100,height:30));root.addSubview(input)
    let button=NSButton(frame:NSRect(x:140,y:20,width:100,height:30));root.addSubview(button)
    let label=NSTextField(labelWithString:"title");label.frame=NSRect(x:20,y:70,width:100,height:30);root.addSubview(label)
    let scroll=NSScrollView(frame:NSRect(x:140,y:70,width:100,height:80));root.addSubview(scroll)
    let grid=NSView(frame:NSRect(x:20,y:160,width:220,height:100));root.addSubview(grid)
    let date=NSButton(frame:NSRect(x:5,y:5,width:40,height:40));grid.addSubview(date)
    for point in [NSPoint(x:40,y:50),NSPoint(x:160,y:50),NSPoint(x:40,y:100),NSPoint(x:160,y:110),NSPoint(x:40,y:190),NSPoint(x:200,y:230)] {
        precondition(!root.permitsBackgroundDrag(at:point))
    }
    // Removing/re-adding a control updates hit-testing immediately; no stale region cache.
    button.removeFromSuperview();precondition(root.permitsBackgroundDrag(at:NSPoint(x:160,y:50)))
    root.addSubview(button);precondition(!root.permitsBackgroundDrag(at:NSPoint(x:160,y:50)))
    print("PASS: panel blank-background drag hit-testing; input/button/label/scroll/calendar descendants preserved")
}
final class FlippedChatView:NSView { override var isFlipped:Bool {true} }
final class ChatController:NSObject {
    private(set) var personaName:String
    let identityTitle=NSTextField(labelWithString:"")
    private var assistantLabels:[(NSTextField,String)]=[]
    func updateIdentity(_ name:String) {
        guard PetSkinRegistry.entries.contains(where:{$0.title==name}) else{return}
        personaName=name;identityTitle.stringValue=name;panel.title=name+"聊天";input.placeholderString="和"+name+"说点什么…"
        for (label,text) in assistantLabels{label.stringValue=name+"\n"+text}
        if busy{status.stringValue=name+"正在想…"}
        panel.contentView?.layoutSubtreeIfNeeded()
    }
    var assistantDisplayedNames:[String]{assistantLabels.map{$0.0.stringValue.components(separatedBy:"\n").first ?? ""}}

    let panel:ChatPanel
    let scroll=NSScrollView()
    let messages=NSStackView()
    let input=NSTextField()
    let status=NSTextField(labelWithString:"聊天仅在本次运行保留")
    let sendButton=NSButton(title:"发送 ↑",target:nil,action:nil)
    static let welcomeText = """
    你可以问我这些哟～
    • 听我讲个笑话，开心一下
    • 偶尔来句暧昧韩语，附中文翻译
    • 跟我说说心情，我会倾听、安慰你，送上一点心灵鸡汤
    """
    private var hasWelcome = false
    var history:[ChatMessage]=[]
    var task:URLSessionDataTask?
    var requestID=UUID()
    var busy=false
    let client=DeepSeekClient()
    init(owner:NSWindow,personaName:String="Ning Ning") {
        self.personaName=PetSkinRegistry.entries.contains{$0.title==personaName} ? personaName:"Ning Ning"
        panel=ChatPanel(contentRect:NSRect(x:0,y:0,width:360,height:330),styleMask:[.borderless],backing:.buffered,defer:false)
        super.init()
        panel.title=self.personaName+"聊天";panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=true;panel.level = .floating;panel.hidesOnDeactivate=false
        panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
        let content=DragBackgroundView(frame:NSRect(x:0,y:0,width:360,height:330))
        if #available(macOS 26.0,*) {
            let glass=NSGlassEffectView(frame:content.bounds);glass.cornerRadius=26;glass.style = .regular
            glass.contentView=content;panel.contentView=glass
        } else {
            let effect=NSVisualEffectView(frame:content.bounds);effect.material = .popover;effect.blendingMode = .behindWindow;effect.state = .active
            effect.wantsLayer=true;effect.layer?.cornerRadius=26;effect.layer?.masksToBounds=true;effect.addSubview(content);panel.contentView=effect
        }
        let title=identityTitle;title.stringValue=self.personaName;title.font = .systemFont(ofSize:18,weight:.semibold);title.frame=NSRect(x:20,y:289,width:240,height:25);content.addSubview(title)
        let subtitle=NSTextField(labelWithString:"陪你聊一会儿");subtitle.font = .systemFont(ofSize:9,weight:.medium);subtitle.textColor = .secondaryLabelColor;subtitle.frame=NSRect(x:20,y:273,width:200,height:16);content.addSubview(subtitle)
        let close=NSButton(title:"×",target:self,action:#selector(closeChat));close.frame=NSRect(x:312,y:286,width:28,height:28);close.bezelStyle = .circular;close.setAccessibilityLabel("关闭聊天");content.addSubview(close)
        scroll.frame=NSRect(x:16,y:84,width:328,height:182);scroll.hasVerticalScroller=true;scroll.drawsBackground=false
        let document=FlippedChatView(frame:NSRect(x:0,y:0,width:328,height:182))
        document.translatesAutoresizingMaskIntoConstraints=false
        messages.orientation = .vertical;messages.alignment = .leading;messages.spacing=12
        messages.translatesAutoresizingMaskIntoConstraints=false
        document.addSubview(messages);scroll.documentView=document
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo:scroll.contentView.widthAnchor),
            messages.leadingAnchor.constraint(equalTo:document.leadingAnchor,constant:4),
            messages.trailingAnchor.constraint(equalTo:document.trailingAnchor,constant:-4),
            messages.topAnchor.constraint(equalTo:document.topAnchor,constant:8),
            messages.bottomAnchor.constraint(equalTo:document.bottomAnchor,constant:-8)
        ])
        content.addSubview(scroll)
        input.frame=NSRect(x:18,y:43,width:246,height:32);input.placeholderString="和"+self.personaName+"说点什么…";input.bezelStyle = .roundedBezel
        input.target=self;input.action=#selector(send);input.setAccessibilityLabel("聊天输入框");content.addSubview(input)
        sendButton.frame=NSRect(x:269,y:43,width:74,height:32);sendButton.bezelStyle = .rounded;sendButton.target=self;sendButton.action=#selector(send);content.addSubview(sendButton)
        status.frame=NSRect(x:20,y:15,width:220,height:20);status.font = .systemFont(ofSize:10);status.textColor = .secondaryLabelColor;content.addSubview(status)
        ensureWelcome()
        position(above:owner)
    }
    func position(above owner:NSWindow) {
        let screen=(owner.screen ?? NSScreen.main)!.visibleFrame
        let x=min(max(owner.frame.midX-180,screen.minX+8),screen.maxX-368)
        let y=min(owner.frame.maxY-8,screen.maxY-338)
        panel.setFrameOrigin(NSPoint(x:x,y:max(screen.minY+8,y)))
    }
    // Local greeting only: no API call and no insertion into conversation history.
    // Keep one greeting for this controller's lifetime, including repeated opens.
    func ensureWelcome() {
        guard !hasWelcome else {return}
        hasWelcome=true
        append(personaName,Self.welcomeText)
        scroll.documentView?.scroll(.zero)
    }
    func show(above owner:NSWindow) {ensureWelcome();position(above:owner);panel.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);panel.makeFirstResponder(input)}
    func append(_ name:String,_ text:String) {
        let row=NSView();row.translatesAutoresizingMaskIntoConstraints=false
        let bubble=NSView();bubble.translatesAutoresizingMaskIntoConstraints=false;bubble.wantsLayer=true
        let isUser=name=="你"
        bubble.layer?.cornerRadius=16
        bubble.layer?.backgroundColor=(isUser ? NSColor.systemPurple.withAlphaComponent(0.17) : NSColor.controlBackgroundColor.withAlphaComponent(0.55)).cgColor
        bubble.layer?.borderWidth=1
        bubble.layer?.borderColor=(isUser ? NSColor.systemPurple.withAlphaComponent(0.3) : NSColor.separatorColor.withAlphaComponent(0.4)).cgColor
        let isAssistant=name != "你" && name != "提示"
        let label=NSTextField(wrappingLabelWithString:(isAssistant ? personaName:name)+"\n"+text)
        if isAssistant{assistantLabels.append((label,text))}
        label.isSelectable=true;label.font = .systemFont(ofSize:14);label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints=false;label.setContentCompressionResistancePriority(.required,for:.vertical)
        label.preferredMaxLayoutWidth=240
        bubble.addSubview(label);row.addSubview(bubble);messages.addArrangedSubview(row)
        NSLayoutConstraint.activate([
            row.widthAnchor.constraint(equalTo:messages.widthAnchor),
            bubble.widthAnchor.constraint(lessThanOrEqualToConstant:268),
            bubble.widthAnchor.constraint(lessThanOrEqualTo:row.widthAnchor,multiplier:0.9),
            bubble.topAnchor.constraint(equalTo:row.topAnchor),bubble.bottomAnchor.constraint(equalTo:row.bottomAnchor),
            label.leadingAnchor.constraint(equalTo:bubble.leadingAnchor,constant:12),label.trailingAnchor.constraint(equalTo:bubble.trailingAnchor,constant:-12),
            label.topAnchor.constraint(equalTo:bubble.topAnchor,constant:10),label.bottomAnchor.constraint(equalTo:bubble.bottomAnchor,constant:-10),
            isUser ? bubble.trailingAnchor.constraint(equalTo:row.trailingAnchor) : bubble.leadingAnchor.constraint(equalTo:row.leadingAnchor)
        ])
        panel.contentView?.layoutSubtreeIfNeeded()
        if let doc=scroll.documentView {doc.scroll(NSPoint(x:0,y:max(0,doc.frame.height-scroll.contentView.bounds.height)))}
    }
    @objc func send() {
        guard !busy else{return}
        let text=input.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !text.isEmpty else{return}
        guard text.count<=8000 else{status.stringValue="消息太长，请缩短至 8000 字以内。";return}
        guard KeyStore.get() != nil else {
            status.stringValue="尚未发送：请在设置中配置聊天 API Key"
            return
        }
        let user=ChatMessage(role:"user",content:text)
        input.stringValue="";append("你",text);busy=true;sendButton.isEnabled=false;status.stringValue=personaName+"正在想…"
        let id=UUID();requestID=id
        task=client.send(history+[user],persona:personaName){[weak self] result in DispatchQueue.main.async {
            guard let self=self,self.requestID==id else{return}
            self.busy=false;self.task=nil;self.sendButton.isEnabled=true
            switch result {
            case .success(let reply):self.history += [user,ChatMessage(role:"assistant",content:reply)];self.history=Array(self.history.suffix(20));self.append(self.personaName,reply);self.status.stringValue="聊天仅在本次运行保留"
            case .failure(let e):self.append("提示",e.localizedDescription);self.status.stringValue="未发送成功，请重新输入后再试"
            }
        }}
    }
    @objc func closeChat() {requestID=UUID();task?.cancel();task=nil;busy=false;sendButton.isEnabled=true;status.stringValue="聊天仅在本次运行保留";panel.orderOut(nil)}
}
