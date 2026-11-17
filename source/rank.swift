import AppKit

struct AIRankSnapshot:Codable {
    let fetchedAt:Date
    let release:String
    let source:String
    let columns:[String]
    let rows:[[String]]
}
enum AIRankError:Error {case invalid,tooLarge,http(Int)}
enum AIRankParser {
    static func capture(_ pattern:String,_ text:String)->String? {
        guard let regex=try? NSRegularExpression(pattern:pattern),let m=regex.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)),let range=Range(m.range(at:1),in:text) else{return nil};return String(text[range])
    }
    static func scriptPath(_ html:String)throws->String {
        guard let path=capture(#"src=["'](\./static/js/main\.[A-Za-z0-9]+\.js)["']"#,html) else{throw AIRankError.invalid};return path
    }
    static func latestRelease(_ js:String)throws->String {
        // The official client publishes a consecutive list of 2.0 release IDs.
        guard let list=capture(#"\[\s*("20[0-9]{6}"(?:\s*,\s*"20[0-9]{6}"){1,30})\s*\]"#,js) else{throw AIRankError.invalid}
        let dates=list.replacingOccurrences(of:"\"",with:"").split(separator:",").map{$0.trimmingCharacters(in:.whitespaces)}
        guard let last=dates.last,dates==dates.sorted(),dates.allSatisfy({validDate($0)}) else{throw AIRankError.invalid};return last
    }
    static func validDate(_ s:String)->Bool {
        let d=DateFormatter();d.locale=Locale(identifier:"en_US_POSIX");d.dateFormat="yyyyMMdd";d.isLenient=false
        guard let date=d.date(from:s) else{return false};return d.string(from:date)==s
    }
    static func csv(_ text:String)throws->[[String]] {
        var rows=[[String]](),row=[String](),field="",quoted=false
        let chars=Array(text);var i=0
        while i<chars.count {let c=chars[i]
            if c=="\"" {if quoted && i+1<chars.count && chars[i+1]=="\"" {field.append("\"");i+=1} else {quoted.toggle()}}
            else if c=="," && !quoted {row.append(field);field=""}
            else if c=="\n" && !quoted {row.append(field.trimmingCharacters(in:.init(charactersIn:"\r")));if row.contains(where:{!$0.isEmpty}){rows.append(row)};row=[];field=""}
            else {field.append(c)}
            i+=1
        }
        guard !quoted else{throw AIRankError.invalid}
        if !field.isEmpty || !row.isEmpty {row.append(field.trimmingCharacters(in:.init(charactersIn:"\r")));rows.append(row)}
        return rows
    }
    static func parse(_ text:String,release:String)throws->AIRankSnapshot {
        let all=try csv(text);let expected=["model","long_agentic","reasoning","coding","browser","data_analysis","research","design"]
        guard validDate(release),all.first==expected,all.count>1,all.count<=1001 else{throw AIRankError.invalid}
        let rows=Array(all.dropFirst())
        guard rows.allSatisfy({r in r.count==8 && !r[0].isEmpty && r[0].count<=160 && r[0].unicodeScalars.allSatisfy{$0.value>=32} && r.dropFirst().allSatisfy{v in v.isEmpty || v=="N/A" || (Double(v).map{$0.isFinite && $0>=0 && $0<=100} ?? false)}}) else{throw AIRankError.invalid}
        return AIRankSnapshot(fetchedAt:Date(),release:release,source:"https://livebench.ai/data/\(release)/table.csv",columns:expected,rows:rows.sorted{(Double($0[1]) ?? -1)>(Double($1[1]) ?? -1)})
    }
}
final class AIRankStore:NSObject,URLSessionTaskDelegate {
    var snapshot:AIRankSnapshot?
    var status="尚未更新"
    var onChange:(()->Void)?
    private var started=false;private var busy=false
    private let cache=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("imnotorange-pet/ai-rank-livebench.json")
    private lazy var session:URLSession={let c=URLSessionConfiguration.ephemeral;c.timeoutIntervalForRequest=20;c.timeoutIntervalForResource=35;c.httpCookieStorage=nil;c.urlCredentialStorage=nil;c.urlCache=nil;return URLSession(configuration:c,delegate:self,delegateQueue:nil)}()
    override init(){super.init();if let d=try? Data(contentsOf:cache),d.count<=1048576,let v=try? JSONDecoder().decode(AIRankSnapshot.self,from:d),v.columns.count==8,v.rows.allSatisfy({$0.count==8}) {snapshot=v;status="上次成功缓存，尚未进行本次检查"}}
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void){completionHandler(nil)}
    func fetch(_ url:URL,limit:Int)async throws->String {
        guard url.scheme=="https",url.host=="livebench.ai" else{throw AIRankError.invalid}
        let (data,response)=try await session.data(from:url)
        guard let http=response as? HTTPURLResponse else{throw AIRankError.invalid}
        guard http.statusCode==200 else{throw AIRankError.http(http.statusCode)}
        guard data.count<=limit,let s=String(data:data,encoding:.utf8) else{throw AIRankError.tooLarge};return s
    }
    func updateOnce(reset:Bool=false){
        guard !busy else{return};if reset{started=false};guard !started else{return};started=true;busy=true;status="正在检查LiveBench官方公开数据…";onChange?()
        Task {
            do {
                let html=try await fetch(URL(string:"https://livebench.ai/")!,limit:200000)
                let path=try AIRankParser.scriptPath(html)
                let js=try await fetch(URL(string:path,relativeTo:URL(string:"https://livebench.ai/"))!.absoluteURL,limit:6000000)
                let release=try AIRankParser.latestRelease(js)
                let csv=try await fetch(URL(string:"https://livebench.ai/data/\(release)/table.csv")!,limit:1000000)
                let next=try AIRankParser.parse(csv,release:release)
                var persisted=true
                do{try FileManager.default.createDirectory(at:cache.deletingLastPathComponent(),withIntermediateDirectories:true);try JSONEncoder().encode(next).write(to:cache,options:.atomic)}catch{persisted=false}
                let saved=persisted
                await MainActor.run {self.busy=false;self.snapshot=next;self.status=saved ? "本次检查更新成功；无后台轮询" : "更新成功，但缓存保存失败";self.onChange?()}
            }catch{
                await MainActor.run {self.busy=false;self.status=self.snapshot == nil ? "本次更新失败，无可用缓存；请查看官方来源" : "本次更新失败，正在显示上次成功缓存（非实时）";self.onChange?()}
            }
        }
    }
}
final class AIRankController:NSObject,NSTableViewDataSource,NSTableViewDelegate {
    let panel:ChatPanel;let owner:NSWindow;let store=AIRankStore();let aa=AARankStore();let arena=ArenaRankStore()
    private var midnightTimer:Timer?
    private var wakeToken:NSObjectProtocol?
    private let dayKey="aiRank.lastScheduledLocalDay"
    private let checkKey="aiRank.lastScheduledCheck"
    let scheduleLabel=NSTextField(labelWithString:"")
    let licenseButton=NSButton(title:"CC BY 4.0 许可",target:nil,action:nil)
    let configure=NSButton(title:"配置 AA key",target:nil,action:nil)
    let tabs=NSSegmentedControl(labels:["Arena","Artificial Analysis","LiveBench"],trackingMode:.selectOne,target:nil,action:nil)
    let status=NSTextField(wrappingLabelWithString:"");let source=NSTextField(labelWithString:"")
    let table=NSTableView();var rows=[[String]]()
    init(owner:NSWindow){
        self.owner=owner;panel=ChatPanel(contentRect:NSRect(x:0,y:0,width:650,height:450),styleMask:[.borderless],backing:.buffered,defer:false);super.init()
        panel.title="AI rank";panel.isOpaque=false;panel.backgroundColor = .clear;panel.level = .floating;panel.hidesOnDeactivate=false;panel.hasShadow=true
        let content=DragBackgroundView(frame:NSRect(x:0,y:0,width:650,height:450))
        if #available(macOS 26.0,*){let glass=NSGlassEffectView(frame:content.bounds);glass.cornerRadius=26;glass.contentView=content;panel.contentView=glass}else{let effect=NSVisualEffectView(frame:content.bounds);effect.material = .popover;effect.state = .active;effect.addSubview(content);panel.contentView=effect}
        let title=NSTextField(labelWithString:"AI rank");title.font = .systemFont(ofSize:20,weight:.semibold);title.frame=NSRect(x:20,y:405,width:400,height:28);content.addSubview(title)
        scheduleLabel.frame=NSRect(x:130,y:410,width:460,height:18);scheduleLabel.font = .systemFont(ofSize:10);scheduleLabel.textColor = .secondaryLabelColor;content.addSubview(scheduleLabel)
        let close=NSButton(title:"×",target:self,action:#selector(hide));close.frame=NSRect(x:602,y:405,width:28,height:28);close.bezelStyle = .circular;content.addSubview(close)
        tabs.frame=NSRect(x:20,y:363,width:610,height:32);tabs.selectedSegment=2;tabs.target=self;tabs.action=#selector(changed);content.addSubview(tabs)
        status.frame=NSRect(x:20,y:300,width:610,height:55);status.font = .systemFont(ofSize:11);content.addSubview(status)
        let scroll=NSScrollView(frame:NSRect(x:20,y:68,width:610,height:225));scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=true;scroll.drawsBackground=false
        table.delegate=self;table.dataSource=self;table.rowHeight=30;table.usesAlternatingRowBackgroundColors=true;table.backgroundColor = .clear;table.headerView=NSTableHeaderView()
        scroll.documentView=table;content.addSubview(scroll)
        source.frame=NSRect(x:20,y:39,width:440,height:21);source.font = .systemFont(ofSize:10);source.textColor = .secondaryLabelColor;content.addSubview(source)
        let link=NSButton(title:"查看官方来源",target:self,action:#selector(openSource));link.bezelStyle = .rounded;link.frame=NSRect(x:480,y:25,width:150,height:30);content.addSubview(link)
        let note=NSTextField(labelWithString:"各榜指标不同，不合并排名；未获授权的数据不抓取、不填猜测值。");note.font = .systemFont(ofSize:9);note.frame=NSRect(x:20,y:15,width:455,height:18);content.addSubview(note)
        configure.frame=NSRect(x:335,y:25,width:135,height:30);configure.bezelStyle = .rounded;configure.target=self;configure.action=#selector(configureAA);content.addSubview(configure)
        licenseButton.frame=NSRect(x:335,y:25,width:135,height:30);licenseButton.bezelStyle = .rounded;licenseButton.target=self;licenseButton.action=#selector(openLicense);content.addSubview(licenseButton)
        arena.onChange={[weak self] in self?.render()}
        aa.onChange={[weak self] in self?.render()}
        store.onChange={[weak self] in self?.render()};render()
    }
    func startUpdates(){
        scheduledCheck(force:true)
        wakeToken=NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main){[weak self] _ in self?.scheduledCheck();self?.scheduleMidnight()}
        scheduleMidnight()
    }
    func scheduledCheck(force:Bool=false){
        let formatter=DateFormatter();formatter.dateFormat="yyyy-MM-dd";formatter.timeZone = .current
        let day=formatter.string(from:Date())
        guard force || UserDefaults.standard.string(forKey:dayKey) != day else{
            store.status=store.snapshot == nil ? "今日已尝试，无可用缓存；下次00:00检查" : "今日已尝试，显示本机成功缓存（不保证实时）"
            arena.status=arena.snapshot == nil ? "今日已尝试，无可用缓存；下次00:00检查" : "今日已尝试，显示本机成功快照（非实时）"
            if aa.snapshot != nil {aa.status="今日已尝试，显示本机成功缓存（不保证实时）"}
            render();return
        }
        UserDefaults.standard.set(day,forKey:dayKey);UserDefaults.standard.set(Date(),forKey:checkKey)
        arena.updateOnce(reset:true);aa.updateOnce(reset:true);store.updateOnce(reset:true)
    }
    private func scheduleMidnight(){
        midnightTimer?.invalidate()
        let calendar=Calendar.current;guard let next=calendar.date(byAdding:.day,value:1,to:calendar.startOfDay(for:Date())) else{return}
        midnightTimer=Timer(fire:next,interval:0,repeats:false){[weak self] _ in self?.scheduledCheck();self?.scheduleMidnight()}
        if let timer=midnightTimer{RunLoop.main.add(timer,forMode:.common)}
    }
    @objc func openLicense(){NSWorkspace.shared.open(URL(string:"https://creativecommons.org/licenses/by/4.0/")!)}
    func show(){let screen=(owner.screen ?? NSScreen.main)!.visibleFrame;panel.setFrameOrigin(NSPoint(x:min(max(owner.frame.midX-325,screen.minX+8),screen.maxX-658),y:max(screen.minY+8,min(owner.frame.maxY-8,screen.maxY-458))));panel.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)}
    @objc func hide(){panel.orderOut(nil)}
    @objc func changed(){render()}
    @objc func configureAA(){
        let alert=NSAlert();alert.messageText="配置 Artificial Analysis 数据API";alert.informativeText="仅在本机输入，保存到Mac本机私有凭据文件；此key只发送到 artificialanalysis.ai 官方免费数据API，不发送聊天服务。保存后立即更新一次，之后每次启动更新。需遵守其数据平台条款及配额。";alert.addButton(withTitle:"保存并更新");alert.addButton(withTitle:"取消")
        let field=NSSecureTextField(frame:NSRect(x:0,y:0,width:320,height:28));field.placeholderString="粘贴 AA 专用 API key";alert.accessoryView=field;alert.window.initialFirstResponder=field
        guard alert.runModal() == .alertFirstButtonReturn else{return}
        let key=field.stringValue.trimmingCharacters(in:.whitespacesAndNewlines);field.stringValue=""
        guard !key.isEmpty,key.count<=1024,!key.unicodeScalars.contains(where:{$0.value<33}) else{status.stringValue="Key格式不正确，未保存";return}
        guard AAKeyStore.save(key)==errSecSuccess else{status.stringValue="本机私有凭据文件保存未成功，请处理系统授权后重试";return}
        aa.update(key:key)
    }
    @objc func openSource(){let links=[ArenaPage.source,"https://artificialanalysis.ai/data-api/docs","https://livebench.ai/"];NSWorkspace.shared.open(URL(string:links[tabs.selectedSegment])!)}
    func render(){
        for column in table.tableColumns {table.removeTableColumn(column)};rows=[]
        licenseButton.isHidden=tabs.selectedSegment != 0
        configure.isHidden=tabs.selectedSegment != 1
        var names=["模型","分数"]
        switch tabs.selectedSegment {
        case 0:
            names=ArenaPage.columns
            if let snap=arena.snapshot {rows=snap.rows;let f=DateFormatter();f.dateFormat="yyyy-MM-dd HH:mm";status.stringValue="Text Arena · raw / overall · Top 100（非风格控制默认榜）\n"+arena.status+"\n发布：\(snap.release) · 获取：\(f.string(from:snap.fetchedAt))"}else{status.stringValue="Text Arena · raw / overall · Top 100\n"+arena.status}
            source.stringValue="来源：Arena / lmarena-ai · HF官方数据集 · CC BY 4.0"
        case 1:
            names=["模型","Intelligence Index","厂商"]
            if let snap=aa.snapshot {rows=snap.rows;let f=DateFormatter();f.dateFormat="yyyy-MM-dd HH:mm";status.stringValue=aa.status+"\n指数版本：\(snap.release) · 获取：\(f.string(from:snap.fetchedAt))（非榜单发布日期）"}
            else {status.stringValue=aa.status}
            source.stringValue="数据来源：Artificial Analysis · 仅本机个人使用"
        default:
            names=["模型","Agentic","推理","编程","浏览器","数据分析","研究","设计"]
            if let s=store.snapshot {rows=s.rows;let f=DateFormatter();f.dateFormat="yyyy-MM-dd HH:mm";status.stringValue="LiveBench 2.0 · 按Agentic降序，非官方总榜名次\n"+store.status+"\n数据版本：\(s.release) · 获取：\(f.string(from:s.fetchedAt))";source.stringValue="来源：LiveBench 官方公开CSV · 分数0–100，空值未测"}else{status.stringValue="LiveBench 2.0\n"+store.status;source.stringValue="来源：livebench.ai · 暂无数据"}
        }
        for (index,name) in names.enumerated(){let c=NSTableColumn(identifier:NSUserInterfaceItemIdentifier(String(index)));c.title=name;c.width=(tabs.selectedSegment==0 ? index==1 : index==0) ? 240:(name=="Intelligence Index" ? 140:90);c.minWidth=60;table.addTableColumn(c)}
        if let checked=UserDefaults.standard.object(forKey:checkKey) as? Date {let f=DateFormatter();f.dateFormat="MM-dd HH:mm";source.toolTip="每日计划检查："+f.string(from:checked)+"；本机00:00，睡眠时下次唤醒补查；每日最多一次，失败保留旧数据"}
        if let checked=UserDefaults.standard.object(forKey:checkKey) as? Date {let f=DateFormatter();f.dateFormat="MM-dd HH:mm";scheduleLabel.stringValue="每天00:00 · 最近计划检查 "+f.string(from:checked)}else{scheduleLabel.stringValue="本机每天00:00检查 · 休眠时唤醒补查"}
        table.reloadData()
    }
    func numberOfRows(in tableView:NSTableView)->Int{rows.count}
    func tableView(_ tableView:NSTableView,viewFor column:NSTableColumn?,row:Int)->NSView? {
        guard let id=column?.identifier.rawValue,let index=Int(id),row<rows.count,index<rows[row].count else{return nil}
        let label=NSTextField(labelWithString:rows[row][index].isEmpty ? "—":rows[row][index]);label.font = .systemFont(ofSize:11);label.lineBreakMode = .byTruncatingTail;label.toolTip=rows[row][index];return label
    }
}
