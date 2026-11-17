import AppKit
import ScriptingBridge
import ApplicationServices

@objc protocol MusicApplication {
    @objc optional var playerState: UInt32 { get }
    @objc optional var playerPosition: Double { get }
    @objc optional var currentTrack: SBObject { get }
}
@objc protocol MusicTrack {
    @objc optional var name: String { get }
    @objc optional var artist: String { get }
    @objc optional var album: String { get }
    @objc optional var persistentID: String { get }
    @objc optional var duration: Double { get }
    @objc optional func artworks() -> SBElementArray
}
@objc protocol MusicArtwork { @objc optional var rawData: Any { get } }
extension SBApplication: MusicApplication {}
extension SBObject: MusicTrack, MusicArtwork {}
struct MusicSample {var id:String;var title:String;var artist:String;var duration:Double;var position:Double;var playing:Bool;var time:Date}
struct MusicEvent:Codable {var id:String;var day:String;var track:String;var title:String;var artist:String;var kind:String;var observedSeconds:Double;var timestamp:Date}
struct MusicDay:Codable {var day:String;var winner:String?;var counts:[String:Int];var settledAt:Date}
func musicDay(_ date:Date)->String {let f=DateFormatter();f.calendar=Calendar(identifier:.gregorian);f.locale=Locale(identifier:"en_US_POSIX");f.dateFormat="yyyy-MM-dd";return f.string(from:date)}
func musicIsToday(_ day:String,now:Date=Date())->Bool {day==musicDay(now)}
// Count only observed playback, never Music's lifetime play count. A pause keeps a
// session, a track change or observed backward loop starts another. Seeking earns no time.
struct MusicCounter {
    var activeTrack:String?;var activeDay:String?
    var last:MusicSample?;var session=UUID().uuidString;var seconds=0.0;var counted=false
    mutating func ingest(_ sample:MusicSample)->[MusicEvent] {
        let previous=last;last=sample
        guard sample.playing else{return []}
        let day=musicDay(sample.time)
        let loop=previous.map{$0.playing && sample.time.timeIntervalSince($0.time)<=8 && $0.position>=max(0,$0.duration-8) && sample.position<=8 && sample.position+2<$0.position} ?? false
        let newSession=activeTrack != sample.id || activeDay != day || loop
        var events:[MusicEvent]=[]
        if newSession {activeTrack=sample.id;activeDay=day;session=UUID().uuidString;seconds=0;counted=false;events.append(MusicEvent(id:session+"-start",day:day,track:sample.id,title:sample.title,artist:sample.artist,kind:"observed_start",observedSeconds:0,timestamp:sample.time))}
        else if let p=previous,p.playing {
            let elapsed=sample.time.timeIntervalSince(p.time),delta=sample.position-p.position
            if elapsed>0 && elapsed<=8 && delta>=0 && delta<=elapsed+2 {seconds += min(elapsed,delta)}
        }
        let threshold=min(30,max(1,sample.duration/2))
        if !counted && seconds>=threshold {counted=true;events.append(MusicEvent(id:session+"-count",day:day,track:sample.id,title:sample.title,artist:sample.artist,kind:"qualified_play",observedSeconds:seconds,timestamp:sample.time))}
        return events
    }
}
struct MusicCoverColor:Codable,Equatable {
    var track:String;var red:Int;var green:Int;var blue:Int
    var valid:Bool{[red,green,blue].allSatisfy{(0...255).contains($0)}}
    var color:NSColor{NSColor(srgbRed:CGFloat(red)/255,green:CGFloat(green)/255,blue:CGFloat(blue)/255,alpha:1)}
    var textColor:NSColor {
        let c=[red,green,blue].map{v -> Double in let n=Double(v)/255;return n<=0.04045 ? n/12.92:pow((n+0.055)/1.055,2.4)}
        let luminance=0.2126*c[0]+0.7152*c[1]+0.0722*c[2]
        return (luminance+0.05)/0.05 >= 1.05/(luminance+0.05) ? .black : .white
    }
    // Deterministic alpha-weighted dominant 32-level RGB bucket, sampled locally.
    // Equal bucket weights choose the lower numeric bucket, never randomness.
    static func extract(_ data:Data,track:String)->MusicCoverColor? {
        guard data.count<=10_000_000,let rep=NSBitmapImageRep(data:data),rep.pixelsWide>0,rep.pixelsHigh>0,rep.pixelsWide<=12000,rep.pixelsHigh<=12000 else{return nil}
        guard let cg=rep.cgImage else{return nil}
        let width=min(64,rep.pixelsWide),height=min(64,rep.pixelsHigh)
        guard let space=CGColorSpace(name:CGColorSpace.sRGB),let context=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:space,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue|CGBitmapInfo.byteOrder32Big.rawValue),let buffer=context.data else{return nil}
        context.interpolationQuality = .medium;context.draw(cg,in:CGRect(x:0,y:0,width:width,height:height))
        let pixels=buffer.bindMemory(to:UInt8.self,capacity:width*height*4)
        var bins:[Int:(weight:Double,r:Double,g:Double,b:Double)]=[:]
        for index in 0..<(width*height) {
            let offset=index*4,w=Double(pixels[offset+3])/255
            guard w>=0.1 else{continue}
            let r=min(255,Double(pixels[offset])/w),g=min(255,Double(pixels[offset+1])/w),b=min(255,Double(pixels[offset+2])/w)
            let key=(Int(r)>>5)*64+(Int(g)>>5)*8+(Int(b)>>5)
            let old=bins[key] ?? (0,0,0,0);bins[key]=(old.weight+w,old.r+r*w,old.g+g*w,old.b+b*w)
        }
        guard let best=bins.sorted(by:{$0.value.weight == $1.value.weight ? $0.key<$1.key:$0.value.weight>$1.value.weight}).first?.value,best.weight>0 else{return nil}
        return MusicCoverColor(track:track,red:Int((best.r/best.weight).rounded()),green:Int((best.g/best.weight).rounded()),blue:Int((best.b/best.weight).rounded()))
    }
}
final class MusicArchive {
    let root:URL
    var events:[MusicEvent]=[];var settled:[String:MusicDay]=[:];var colors:[String:MusicCoverColor]=[:];var error:String?
    init(root:URL=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/imnotorange-pet/Music Calendar")) {
        self.root=root
        do {
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
            for year in try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil) where year.lastPathComponent.count==4 {
                let raw=year.appendingPathComponent("events.jsonl")
                if let data=try? String(contentsOf:raw,encoding:.utf8) {for line in data.split(separator:"\n") {if let d=line.data(using:.utf8),let e=try? JSONDecoder().decode(MusicEvent.self,from:d){events.append(e)}else{error="部分原始记录损坏，已保留文件；统计可能不完整"}}}
                if let data=try? Data(contentsOf:year.appendingPathComponent("days.json")),let days=try? JSONDecoder().decode([String:MusicDay].self,from:data){settled.merge(days){old,_ in old}}
                if let data=try? Data(contentsOf:year.appendingPathComponent("colors.json")),let cached=try? JSONDecoder().decode([String:MusicCoverColor].self,from:data){colors.merge(cached.filter{$0.value.valid}){old,_ in old}}
            }
        }catch{self.error="无法读取本机音乐记录：\(error.localizedDescription)"}
        backfillColors()
    }
    func yearURL(_ day:String)throws->URL {let dir=root.appendingPathComponent(String(day.prefix(4)));try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);return dir}
    func append(_ event:MusicEvent) {
        guard !events.contains(where:{$0.id==event.id}) else{return}
        do {
            let url=try yearURL(event.day).appendingPathComponent("events.jsonl")
            if !FileManager.default.fileExists(atPath:url.path){FileManager.default.createFile(atPath:url.path,contents:nil)}
            let h=try FileHandle(forWritingTo:url);defer{try? h.close()};try h.seekToEnd();var d=try JSONEncoder().encode(event);d.append(10);try h.write(contentsOf:d);try h.synchronize();events.append(event)
        }catch{self.error="记录写入失败：\(error.localizedDescription)"}
    }
    func counts(_ day:String)->[String:Int] {var c:[String:Int]=[:];for e in events where e.day==day && e.kind=="qualified_play" {c[e.track,default:0]+=1};return c}
    func settle(before today:String,now:Date=Date()) {
        for day in Set(events.map{$0.day}).sorted() where day<today && settled[day]==nil {
            let counts=counts(day);let high=counts.values.max();let tied=counts.keys.filter{counts[$0]==high}.sorted()
            let result=MusicDay(day:day,winner:tied.randomElement(),counts:counts,settledAt:now)
            do {let dir=try yearURL(day);var yearly=settled.filter{$0.key.hasPrefix(String(day.prefix(4)))};yearly[day]=result;try JSONEncoder().encode(yearly).write(to:dir.appendingPathComponent("days.json"),options:.atomic);settled[day]=result;cacheColor(day)}
            catch {self.error="结算保存失败：\(error.localizedDescription)"}
        }
    }
    func backfillColors(){for day in settled.keys.sorted(){cacheColor(day)}}
    func cacheColor(_ day:String){
        guard let winner=settled[day]?.winner,colors[day]?.track != winner,let file=artworkURL(day:day,track:winner),let data=try? Data(contentsOf:file),let color=MusicCoverColor.extract(data,track:winner) else{return}
        do {
            let dir=try yearURL(day);var yearly=colors.filter{$0.key.hasPrefix(String(day.prefix(4)))};yearly[day]=color
            try JSONEncoder().encode(yearly).write(to:dir.appendingPathComponent("colors.json"),options:.atomic);colors[day]=color
        }catch{self.error="封面颜色缓存保存失败；原始记录未改动"}
    }
    func artworkURL(day:String,track:String)->URL? {guard let dir=try? yearURL(day) else{return nil};let safe=Data(track.utf8).base64EncodedString().replacingOccurrences(of:"/",with:"_");return dir.appendingPathComponent("cover-"+safe+".png")}
    func title(_ track:String)->String {guard let e=events.last(where:{$0.track==track}) else{return track};return e.title+"\n"+e.artist}
}
enum MusicCalendarPlayback {
    static func persistentID(_ value:String?)->String? {
        guard let value=value,value.range(of:"^[0-9A-Fa-f]{16}$",options:.regularExpression) != nil else{return nil}
        return value.uppercased()
    }
    static func target(day:String,winner:String?,now:Date=Date())->String? {
        guard day<musicDay(now) else{return nil}
        return persistentID(winner)
    }
    static func scriptSource(_ id:String)->String {
        return """
        with timeout of 5 seconds
            tell application id "com.apple.Music"
                set matches to (every track of library playlist 1 whose persistent ID is "\(id)")
                if (count of matches) is not 1 then return "missing"
                set chosenTrack to item 1 of matches
                if persistent ID of chosenTrack is not "\(id)" then return "missing"
                play chosenTrack once true
                return "requested"
            end tell
        end timeout
        """
    }
    // Called only by an explicit historical-date click. Never by polling or tests.
    static func playExact(_ id:String)->String {
        guard let id=persistentID(id) else{return "这条记录没有可靠歌曲标识，不会按歌名猜测播放。"}
        guard !NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.Music").isEmpty else{return "请先打开 Apple Music，再点击该日期播放。"}
        guard MusicCalendarController.permission(prompt:false)==noErr else{return "Music 自动化未授权；请由你在系统设置中允许后再点击，不会自动弹窗。"}
        // ID is exactly 16 hex characters. No track name or user text enters script source.
        let source=scriptSource(id)
        var failure:NSDictionary?
        guard let script=NSAppleScript(source:source) else{return "无法建立 Music 播放请求，未播放。"}
        let result=script.executeAndReturnError(&failure)
        if failure != nil{return "Music 未能执行播放，请检查歌曲是否仍在资料库及可用。"}
        return result.stringValue == "requested" ? "已向 Apple Music 发送该日胜出歌曲的播放请求。" : "资料库中找不到唯一对应歌曲，可能已移除；没有播放其他歌曲。"
    }
}
// Explicit layout keeps the song name visible even when artwork is present.
// Decorative content never intercepts a click intended for the date button.
final class MusicDateContent:NSView {
    override var isFlipped:Bool{true}
    override func hitTest(_ point:NSPoint)->NSView?{nil}
}
@discardableResult func musicDateContent(button:NSButton,date:Int,song:String,artist:String,image:NSImage?,foreground:NSColor)->NSTextField {
    button.title="";button.image=nil
    let content=MusicDateContent(frame:button.bounds)
    let dateLabel=NSTextField(labelWithString:String(date));dateLabel.frame=NSRect(x:53,y:5,width:26,height:18);dateLabel.font = .systemFont(ofSize:11,weight:.medium);dateLabel.alignment = .right;dateLabel.textColor=foreground;content.addSubview(dateLabel)
    if let image=image {let thumbnail=NSImageView(frame:NSRect(x:5,y:3,width:24,height:24));thumbnail.image=image;thumbnail.imageScaling = .scaleProportionallyUpOrDown;content.addSubview(thumbnail)}
    let title=NSTextField(wrappingLabelWithString:song);title.frame=NSRect(x:5,y:29,width:74,height:36);title.font = .systemFont(ofSize:10,weight:.medium);title.textColor=foreground;title.alignment = .left;title.maximumNumberOfLines=3;title.lineBreakMode = .byWordWrapping;content.addSubview(title)
    button.addSubview(content);button.setAccessibilityLabel("\(date)，\(song)，\(artist)");return title
}
final class MusicCalendarController:NSObject {
    let owner:NSWindow;let panel:ChatPanel;let archive=MusicArchive();var counter=MusicCounter()
    let year=NSPopUpButton();let month=NSPopUpButton();let toggle=NSButton();let status=NSTextField(wrappingLabelWithString:"");let grid=NSView()
    var timer:Timer?;var polling=false;private var playbackPending=false;var enabled=UserDefaults.standard.bool(forKey:"musicCalendar.enabled")
    var displayedLocalDay=musicDay(Date())
    var lastError:String?;private var artworkTrack:String?;let queue=DispatchQueue(label:"pet.music.read")
    init(owner:NSWindow) {
        self.owner=owner;panel=ChatPanel(contentRect:NSRect(x:0,y:0,width:650,height:650),styleMask:[.borderless],backing:.buffered,defer:false)
        super.init();panel.title="Music Calendar";panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=true;panel.level = .floating;panel.hidesOnDeactivate=false;panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
        let content=DragBackgroundView(frame:NSRect(x:0,y:0,width:650,height:650))
        if #available(macOS 26,*) {let glass=NSGlassEffectView(frame:content.bounds);glass.cornerRadius=26;glass.contentView=content;panel.contentView=glass} else {let glass=NSVisualEffectView(frame:content.bounds);glass.material = .popover;glass.state = .active;glass.addSubview(content);panel.contentView=glass}
        let title=NSTextField(labelWithString:"Music Calendar");title.font = .systemFont(ofSize:20,weight:.semibold);title.frame=NSRect(x:22,y:606,width:350,height:28);content.addSubview(title)
        let close=NSButton(title:"×",target:self,action:#selector(closePanel));close.frame=NSRect(x:598,y:603,width:30,height:30);content.addSubview(close)
        let years=Set(archive.events.map{String($0.day.prefix(4))}+[String(Calendar.current.component(.year,from:Date()))]).sorted();year.addItems(withTitles:years);year.selectItem(withTitle:String(Calendar.current.component(.year,from:Date())));year.frame=NSRect(x:22,y:566,width:100,height:28)
        month.addItems(withTitles:(1...12).map{"\($0)月"});month.selectItem(at:Calendar.current.component(.month,from:Date())-1);month.frame=NSRect(x:132,y:566,width:90,height:28)
        for select in [year,month]{select.target=self;select.action=#selector(render);content.addSubview(select)}
        toggle.frame=NSRect(x:350,y:566,width:275,height:28);toggle.target=self;toggle.action=#selector(changeEnabled);content.addSubview(toggle)
        grid.frame=NSRect(x:20,y:100,width:610,height:450);content.addSubview(grid)
        status.frame=NSRect(x:22,y:43,width:605,height:52);status.font = .systemFont(ofSize:11);content.addSubview(status)
        let folder=NSButton(title:"打开年度归档文件夹",target:self,action:#selector(openArchive));folder.frame=NSRect(x:22,y:10,width:190,height:28);content.addSubview(folder)
        let note=NSTextField(labelWithString:"仅本机记录 · 不补造未监听播放 · 不向模型发送");note.font = .systemFont(ofSize:10);note.frame=NSRect(x:230,y:17,width:390,height:18);content.addSubview(note)
        timer=Timer.scheduledTimer(withTimeInterval:3,repeats:true){[weak self]_ in self?.tick()};RunLoop.main.add(timer!,forMode:.common)
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(wake),name:NSWorkspace.didWakeNotification,object:nil)
        archive.settle(before:musicDay(Date()));render()
    }
    @objc func wake(){counter=MusicCounter();tick()}
    @objc func closePanel(){panel.orderOut(nil)}
    func show(){let s=(owner.screen ?? NSScreen.main)!.visibleFrame;panel.setFrameOrigin(NSPoint(x:max(s.minX,min(owner.frame.midX-325,s.maxX-650)),y:max(s.minY,min(owner.frame.maxY-8,s.maxY-650))));panel.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);render()}
    @objc func changeEnabled(){
        enabled.toggle();UserDefaults.standard.set(enabled,forKey:"musicCalendar.enabled");counter=MusicCounter();lastError=nil;render()
        if enabled {queue.async{let result=Self.permission(prompt:true);DispatchQueue.main.async{if result != noErr{self.lastError="Music 自动化未获允许；请在系统设置中由你授权"};self.tick();self.render()}}}
    }
    static func permission(prompt:Bool)->OSStatus {
        let bundle="com.apple.Music"
        var target=AEAddressDesc()
        let status=bundle.withCString{AECreateDesc(DescType(typeApplicationBundleID),$0,bundle.utf8.count,&target)}
        guard status==noErr else{return OSStatus(status)};defer{AEDisposeDesc(&target)}
        return AEDeterminePermissionToAutomateTarget(&target,AEEventClass(typeWildCard),AEEventID(typeWildCard),prompt)
    }
    @objc func openArchive(){NSWorkspace.shared.open(archive.root)}
    func tick(){
        let today=musicDay(Date());archive.settle(before:today)
        if today != displayedLocalDay {displayedLocalDay=today;if panel.isVisible{render()}}
        guard enabled,!polling else{return};polling=true
        queue.async { [weak self] in
            guard let self=self else{return}
            var sample:MusicSample?;var cover:Data?;var message:String?
            // Never launch/play Music or prompt here. Sample only while calendar recording is enabled.
            if NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.Music").isEmpty {message="等待 Apple Music 播放"}
            else if Self.permission(prompt:false) != noErr {message="Music 自动化未授权；请暂停后重新点击启用，由你处理授权"}
            else if let pid=NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.Music").first?.processIdentifier,let app=SBApplication(processIdentifier:pid) {
                app.timeout=5*60
                let m=app as MusicApplication
                if let state=m.playerState,state==0x6b505350,let track=m.currentTrack {
                    let t=track as MusicTrack
                    if let name=t.name,!name.isEmpty,let pos=m.playerPosition {
                        let artist=t.artist ?? "未知歌手",id=t.persistentID ?? ""
                        sample=MusicSample(id:id.isEmpty ? name+"|"+artist+(t.album ?? ""):id,title:name,artist:artist,duration:t.duration ?? 180,position:pos,playing:true,time:Date())
                        if self.artworkTrack != sample?.id {self.artworkTrack=sample?.id;if let first=t.artworks?().firstObject as? SBObject {let raw=(first as MusicArtwork).rawData; if let data=raw as? Data {cover=data} else if let descriptor=raw as? NSAppleEventDescriptor {cover=descriptor.data}}}
                    }else{message="未获得歌曲信息；请检查自动化授权"}
                }else{message="Music 暂停、未播放，或尚未授权"}
            }
            DispatchQueue.main.async {
                self.polling=false
                guard self.enabled else{self.counter=MusicCounter();return}
                if let sample=sample {
                    let events=self.counter.ingest(sample);events.forEach{self.archive.append($0)}
                    if let data=cover,data.count<10_000_000,let image=NSImage(data:data),let tiff=image.tiffRepresentation,let rep=NSBitmapImageRep(data:tiff),let png=rep.representation(using:.png,properties:[:]),let url=self.archive.artworkURL(day:musicDay(sample.time),track:sample.id),!FileManager.default.fileExists(atPath:url.path){try? png.write(to:url,options:.atomic)}
                    self.lastError="正在记录："+sample.title
                }else {if var p=self.counter.last{p.playing=false;p.time=Date();_ = self.counter.ingest(p)};self.lastError=message}
                if self.panel.isVisible{self.render()}
            }
        }
    }
    @objc func render(){
        displayedLocalDay=musicDay(Date())
        let currentYear=String(Calendar.current.component(.year,from:Date()));if !year.itemTitles.contains(currentYear){year.addItem(withTitle:currentYear)}
        toggle.title=enabled ? "暂停本机监听" : "启用监听（由你允许 Music 权限）"
        grid.subviews.forEach{$0.removeFromSuperview()}
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone = .current
        let y=Int(year.titleOfSelectedItem ?? "") ?? calendar.component(.year,from:Date()),m=month.indexOfSelectedItem+1
        guard let first=calendar.date(from:DateComponents(year:y,month:m,day:1)),let days=calendar.range(of:.day,in:.month,for:first) else{return}
        let offset=(calendar.component(.weekday,from:first)+5)%7
        for (i,label) in ["一","二","三","四","五","六","日"].enumerated(){let t=NSTextField(labelWithString:label);t.frame=NSRect(x:i*87,y:428,width:80,height:20);t.alignment = .center;grid.addSubview(t)}
        for d in days {
            let date=calendar.date(from:DateComponents(year:y,month:m,day:d))!,day=musicDay(date),index=offset+d-1
            let winner=archive.settled[day]?.winner
            let button=NSButton(title:String(d)+(winner==nil ? "": "\n"+archive.title(winner!).replacingOccurrences(of:"\n",with:" · ")),target:self,action:#selector(dayDetails(_:)))
            button.identifier=NSUserInterfaceItemIdentifier(day);button.frame=NSRect(x:(index%7)*87,y:356-(index/7)*70,width:84,height:68);button.bezelStyle = .regularSquare;button.font = .systemFont(ofSize:9);button.cell?.wraps=true;button.toolTip=winner.map{archive.title($0)+(day<musicDay(Date()) ? " · 点击在 Apple Music 播放" : "")} ?? "无已结算记录"
            var cover:NSImage?
            if let winner=winner,let url=archive.artworkURL(day:day,track:winner){cover=NSImage(contentsOf:url)}
            if let color=archive.colors[day],color.track==winner,color.valid {
                button.isBordered=false;button.wantsLayer=true;button.layer?.cornerRadius=10
                button.layer?.backgroundColor=color.color.cgColor
                button.contentTintColor=color.textColor
                let paragraph=NSMutableParagraphStyle();paragraph.alignment = .center;paragraph.lineBreakMode = .byWordWrapping
                button.attributedTitle=NSAttributedString(string:button.title,attributes:[.foregroundColor:color.textColor,.font:NSFont.systemFont(ofSize:9),.paragraphStyle:paragraph])
            }
            if let winner=winner {
                let event=archive.events.last(where:{$0.track==winner})
                let foreground=archive.colors[day].flatMap{$0.track==winner && $0.valid ? $0.textColor:nil} ?? NSColor.labelColor
                musicDateContent(button:button,date:d,song:event?.title ?? winner,artist:event?.artist ?? "",image:cover,foreground:foreground)
            }
            if musicIsToday(day) {
                button.isBordered=false;button.wantsLayer=true
                if archive.colors[day]==nil {button.layer?.backgroundColor=NSColor.systemPurple.withAlphaComponent(0.23).cgColor}
                button.layer?.cornerRadius=10;button.layer?.borderWidth=1.5
                button.layer?.borderColor=NSColor.systemPurple.withAlphaComponent(0.75).cgColor
                if archive.colors[day]==nil {button.contentTintColor = .labelColor}
                let heart=NSTextField(labelWithString:"💜")
                heart.frame=NSRect(x:3,y:button.isFlipped ? 2 : 46,width:22,height:20);heart.font = .systemFont(ofSize:13)
                heart.isSelectable=false;heart.setAccessibilityElement(false);button.addSubview(heart)
                button.setAccessibilityLabel("今天，"+day+(winner.map{"，"+archive.title($0)} ?? ""))
                button.toolTip="今天 · "+(button.toolTip ?? day)
            }
            let menu=NSMenu();let details=NSMenuItem(title:"查看当日记录（不播放）",action:#selector(dateRecordMenu(_:)),keyEquivalent:"")
            details.target=self;details.representedObject=day;menu.addItem(details);button.menu=menu
            grid.addSubview(button)
        }
        status.stringValue=(archive.error ?? lastError ?? (enabled ? "等待 Music 播放与系统授权" : "尚未启用；只记录启用后的实际播放"))+"\n连续观察满30秒或半首（较短者）计1次；暂停不重复，跳进度不计时。午夜固定平局随机结果，睡眠后补结算。"
    }
    @objc func dayDetails(_ sender:NSButton){guard let day=sender.identifier?.rawValue else{return}
        if day<musicDay(Date()),let winner=archive.settled[day]?.winner {
            guard let id=MusicCalendarPlayback.target(day:day,winner:winner) else{lastError="这条历史记录缺少可靠歌曲标识，不会按歌名猜测播放。";render();return}
            guard !playbackPending else{lastError="正在处理上一条播放请求，请稍候。";render();return}
            playbackPending=true;lastError="正在查找该日胜出歌曲…";render()
            queue.async{[weak self] in
                let result=MusicCalendarPlayback.playExact(id)
                DispatchQueue.main.async{guard let self=self else{return};self.playbackPending=false;self.lastError=result;self.render()}
            }
            return
        }
        showDayRecord(day)
    }
    @objc func dateRecordMenu(_ item:NSMenuItem){if let day=item.representedObject as? String{showDayRecord(day)}}
    func showDayRecord(_ day:String){
        let counts=archive.counts(day);let starts=archive.events.filter{$0.day==day && $0.kind=="observed_start"}.count
        let alert=NSAlert();alert.messageText=day;alert.informativeText="观察到的播放片段：\(starts)；有效播放：\(counts.values.reduce(0,+))\n"+(counts.isEmpty ? "没有记录；不代表当天没听歌。":counts.sorted{$0.value>$1.value}.map{archive.title($0.key).replacingOccurrences(of:"\n",with:" · ")+"：\($0.value)次"}.joined(separator:"\n"))+"\n"+(archive.settled[day] == nil ? "尚未结算，今日数据会继续累计。":"已结算，平局结果已固定保存。");alert.beginSheetModal(for:panel)
    }
}

func musicSelfTest(){
    let tile=NSButton(frame:NSRect(x:0,y:0,width:84,height:68))
    let testImage=NSImage(size:NSSize(width:24,height:24))
    let titleWithCover=musicDateContent(button:tile,date:15,song:"胜出歌曲测试名称",artist:"歌手",image:testImage,foreground:.white)
    precondition(titleWithCover.stringValue=="胜出歌曲测试名称" && tile.bounds.contains(titleWithCover.frame))
    precondition(titleWithCover.frame.height>=30 && tile.image==nil)
    precondition((tile.subviews.last as? MusicDateContent)?.hitTest(.zero)==nil)
    let noCover=NSButton(frame:tile.frame)
    precondition(musicDateContent(button:noCover,date:14,song:"No cover song",artist:"Artist",image:nil,foreground:.black).stringValue=="No cover song")
    print("PASS: date tile song label reserved with/without artwork, readable text area and click passthrough")
    let playbackToday=musicDay(Date())
    precondition(MusicCalendarPlayback.target(day:playbackToday,winner:"0123456789ABCDEF")==nil)
    precondition(MusicCalendarPlayback.target(day:"2099-01-01",winner:"0123456789ABCDEF")==nil)
    precondition(MusicCalendarPlayback.target(day:"2020-01-01",winner:"0123456789abcdef")=="0123456789ABCDEF")
    precondition(MusicCalendarPlayback.target(day:"2020-01-01",winner:nil)==nil)
    precondition(MusicCalendarPlayback.target(day:"2020-01-01",winner:"title|artist|album")==nil)
    precondition(MusicCalendarPlayback.persistentID("0123456789ABCDZZ")==nil)
    precondition(MusicCalendarPlayback.persistentID("0123456789ABCDEF\nplay") == nil)
    var scriptError:NSDictionary?
    let compiled=NSAppleScript(source:MusicCalendarPlayback.scriptSource("0123456789ABCDEF"))!.compileAndReturnError(&scriptError)
    precondition(compiled,"Music playback script failed dictionary compilation")
    print("PASS: historic-click exact-ID validation and Music dictionary script compilation; no playback executed")
    let testCalendar=Calendar(identifier:.gregorian)
    let end=testCalendar.date(from:DateComponents(year:2025,month:12,day:31,hour:23,minute:59,second:59))!
    precondition(musicIsToday("2025-12-31",now:end))
    precondition(!musicIsToday("2024-12-31",now:end) && !musicIsToday("2025-11-30",now:end))
    let next=end.addingTimeInterval(1)
    precondition(musicIsToday("2026-01-01",now:next) && !musicIsToday("2025-12-31",now:next))
    var c=MusicCounter();let base=Calendar.current.date(from:DateComponents(year:2025,month:12,day:31,hour:12))!
    func sample(_ t:Double,_ p:Double,_ playing:Bool=true,_ id:String="song")->MusicSample{MusicSample(id:id,title:"Test",artist:"Artist",duration:60,position:p,playing:playing,time:base.addingTimeInterval(t))}
    var e=c.ingest(sample(0,0));for t in stride(from:3.0,through:30.0,by:3){e += c.ingest(sample(t,t))};precondition(e.filter{$0.kind=="qualified_play"}.count==1)
    _=c.ingest(sample(33,30,false));_=c.ingest(sample(36,30));precondition(c.ingest(sample(39,33)).isEmpty)
    // Backward seek does not create another count, observed end-to-start does.
    precondition(c.ingest(sample(42,5)).isEmpty)
    _=c.ingest(sample(45,58));e=c.ingest(sample(48,1));precondition(e.count==1)
    for t in stride(from:51.0,through:78.0,by:3){e += c.ingest(sample(t,t-47))};precondition(e.filter{$0.kind=="qualified_play"}.count==1)
    var skip=MusicCounter();_=skip.ingest(sample(0,0));_=skip.ingest(sample(3,40));precondition(skip.seconds==0);_=skip.ingest(sample(100,50));precondition(skip.seconds==0)
    let first=skip.ingest(sample(103,0,true,"other"));precondition(first.count==1)
    let nextYear=Calendar.current.date(from:DateComponents(year:2026,month:1,day:1,hour:0))!
    let midnight=MusicSample(id:"other",title:"Test",artist:"Artist",duration:60,position:3,playing:true,time:nextYear)
    precondition(skip.ingest(midnight).count==1 && skip.seconds==0)
    let dir=FileManager.default.temporaryDirectory.appendingPathComponent("pet-music-test-"+UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:dir)}
    let a=MusicArchive(root:dir)
    for id in ["a","b"] {a.append(MusicEvent(id:id,day:"2025-12-31",track:id,title:id,artist:"Test",kind:"qualified_play",observedSeconds:30,timestamp:base))}
    a.settle(before:"2026-01-01");let winner=a.settled["2025-12-31"]?.winner;precondition(winner != nil)
    a.settle(before:"2026-02-01");precondition(a.settled["2025-12-31"]?.winner==winner)
    func imageData(_ color:NSColor)->Data {
        let space=CGColorSpace(name:CGColorSpace.sRGB)!
        let context=CGContext(data:nil,width:4,height:4,bitsPerComponent:8,bytesPerRow:16,space:space,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue|CGBitmapInfo.byteOrder32Big.rawValue)!
        context.setFillColor(color.cgColor);context.fill(CGRect(x:0,y:0,width:4,height:4))
        return NSBitmapImageRep(cgImage:context.makeImage()!).representation(using:.png,properties:[:])!
    }
    let red=imageData(NSColor(srgbRed:1,green:0,blue:0,alpha:1))
    let dominant=MusicCoverColor.extract(red,track:"test")!
    precondition(dominant.red==255 && dominant.green==0 && dominant.blue==0)
    precondition(MusicCoverColor.extract(red,track:"test")==dominant)
    precondition(MusicCoverColor.extract(imageData(NSColor(srgbRed:0,green:0,blue:0,alpha:0)),track:"test")==nil)
    precondition(MusicCoverColor.extract(Data("invalid".utf8),track:"test")==nil)
    precondition(a.colors["2025-12-31"]==nil) // Missing artwork retains normal date styling.
    try! red.write(to:a.artworkURL(day:"2025-12-31",track:winner!)!)
    let beforeBackfill=a.settled["2025-12-31"]!.winner
    a.backfillColors();precondition(a.colors["2025-12-31"]?.red==255)
    precondition(a.settled["2025-12-31"]!.winner==beforeBackfill && a.events.count==2)
    let reload=MusicArchive(root:dir);precondition(reload.events.count==2 && reload.settled["2025-12-31"]?.winner==winner && reload.colors["2025-12-31"]==a.colors["2025-12-31"])
    print("PASS: local cover colors: solid, transparent, invalid/missing, deterministic, safe historic backfill and yearly reload")
    precondition(FileManager.default.fileExists(atPath:dir.appendingPathComponent("2025/events.jsonl").path))
    print("PASS: Music today highlight/year-month-midnight, pause, resume, seeks, loop, gaps, year archive, fixed ties, reload")
}

func musicReadOnlyProbe(){
    guard MusicCalendarController.permission(prompt:false)==noErr else{print("Music probe: authorization unavailable; no prompt requested");return}
    guard let pid=NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.Music").first?.processIdentifier,let app=SBApplication(processIdentifier:pid) else{print("Music probe: not running; not launched");return}
    app.timeout=5*60;let music=app as MusicApplication
    guard let track=music.currentTrack else{print("Music probe: no current track");return}
    let t=track as MusicTrack;let metadata=t.name != nil && music.playerPosition != nil
    var decoded=false
    if let first=t.artworks?().firstObject as? SBObject {
        let raw=(first as MusicArtwork).rawData
        let data=(raw as? Data) ?? (raw as? NSAppleEventDescriptor)?.data
        if let data=data{decoded=NSImage(data:data) != nil}
    }
    print("Music probe: metadata=\(metadata), artworkDecoded=\(decoded); safe text fallback otherwise; no playback changes")
}
