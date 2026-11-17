import AppKit
import CryptoKit

struct GalleryItem:Codable,Equatable {
    var title:String;var link:String;var date:Date?;var imageURL:String?;var ningning:Bool
}

enum GalleryRules {
    static let feed=URL(string:"https://aespa-official.jp/feed/")!
    static let interval:TimeInterval=3600
    static func due(_ last:Date?,now:Date=Date())->Bool {last.map{now.timeIntervalSince($0)>=interval} ?? true}
    static func safeURL(_ text:String,image:Bool=false)->URL? {
        guard text.utf8.count<2048,let c=URLComponents(string:text),c.scheme=="https",["aespa-official.jp","aespa.com"].contains(c.host ?? ""),c.user==nil,c.password==nil,c.port==nil,c.query==nil,c.fragment==nil,!c.percentEncodedPath.contains("%"),!c.path.contains(".."),!c.path.contains("\\"),let u=c.url else{return nil}
        if c.host=="aespa-official.jp" {
            if image {guard c.path.hasPrefix("/aspect/wp-content/uploads/"),["jpg","jpeg","png","webp"].contains(u.pathExtension.lowercased()) else{return nil}}
            else {guard c.path.hasPrefix("/news/") else{return nil}}
        }else if image {
            guard c.path.range(of:#"^/assets/lemonade/slides_a/(0_aespa/\([1-3]\)aespa-lemonade|4_ningning/\([1-7]\)ningning-lemonade)\.jpg$"#,options:.regularExpression) != nil else{return nil}
        }else{guard c.path=="/" else{return nil}}
        return u
    }
    static func decoded(_ input:String)->String {
        var output=input
        let regex=try! NSRegularExpression(pattern:"&#(x[0-9a-fA-F]+|[0-9]+);")
        for match in regex.matches(in:output,range:NSRange(output.startIndex...,in:output)).reversed(){
            guard let r=Range(match.range(at:1),in:output),let whole=Range(match.range,in:output) else{continue}
            let code=String(output[r]);let n=code.hasPrefix("x") ? UInt32(code.dropFirst(),radix:16):UInt32(code)
            if let n=n,let scalar=UnicodeScalar(n){output.replaceSubrange(whole,with:String(scalar))}
        }
        for (a,b) in [("&amp;","&"),("&quot;","\""),("&apos;","'"),("&lt;","<"),("&gt;",">"),("&nbsp;"," ")]{output=output.replacingOccurrences(of:a,with:b)}
        return output
    }
    static func visibleText(_ html:String)->String {
        var text=html.replacingOccurrences(of:"(?is)<(script|style)\\b[^>]*>.*?</\\1\\s*>",with:" ",options:.regularExpression)
        text=text.replacingOccurrences(of:"(?s)<!--.*?-->|<[^>]*>",with:" ",options:.regularExpression)
        return decoded(text).replacingOccurrences(of:"\\s+",with:" ",options:.regularExpression).trimmingCharacters(in:.whitespacesAndNewlines)
    }
    static func isNingning(_ text:String)->Bool {let folded=text.folding(options:[.caseInsensitive,.widthInsensitive],locale:Locale(identifier:"en_US_POSIX"));return ["ningning","宁艺卓","ニンニン","닝닝"].contains{folded.contains($0)}}
    static func firstImage(_ html:String)->String? {
        let tags=try! NSRegularExpression(pattern:"(?is)<img\\b[^>]*>")
        let src=try! NSRegularExpression(pattern:"(?is)(?:^|\\s)src\\s*=\\s*([\"'])(.*?)\\1")
        for tag in tags.matches(in:html,range:NSRange(html.startIndex...,in:html)) {
            guard let r=Range(tag.range,in:html) else{continue};let value=String(html[r])
            guard let m=src.firstMatch(in:value,range:NSRange(value.startIndex...,in:value)),let sr=Range(m.range(at:2),in:value) else{continue}
            if let u=safeURL(decoded(String(value[sr])),image:true){return u.absoluteString}
        };return nil
    }
}
final class GalleryFeedParser:NSObject,XMLParserDelegate {
    var items:[GalleryItem]=[];private var inItem=false;private var field="";private var values:[String:String]=[:]
    static func parse(_ data:Data)throws->[GalleryItem] {
        guard data.count<=1_000_000,let xml=String(data:data,encoding:.utf8),!xml.uppercased().contains("<!DOCTYPE"),!xml.uppercased().contains("<!ENTITY") else{throw NSError(domain:"Gallery",code:1)}
        let handler=GalleryFeedParser();let parser=XMLParser(data:data);parser.shouldResolveExternalEntities=false;parser.delegate=handler
        guard parser.parse(),!handler.items.isEmpty else{throw NSError(domain:"Gallery",code:2)}
        var seen=Set<String>();return handler.items.filter{seen.insert($0.link).inserted}.sorted{($0.date ?? .distantPast) == ($1.date ?? .distantPast) ? $0.link<$1.link:($0.date ?? .distantPast)>($1.date ?? .distantPast)}
    }
    func parser(_ parser:XMLParser,didStartElement name:String,namespaceURI:String?,qualifiedName:String?,attributes:[String:String]){
        if name=="item"{inItem=true;values=[:]};if inItem{field=name}
    }
    func parser(_ parser:XMLParser,foundCharacters string:String){if inItem{values[field,default:""]+=string}}
    func parser(_ parser:XMLParser,foundCDATA data:Data){if inItem,let text=String(data:data,encoding:.utf8){values[field,default:""]+=text}}
    func parser(_ parser:XMLParser,resolveExternalEntityName name:String,systemID:String?)->Data?{nil}
    func parser(_ parser:XMLParser,didEndElement name:String,namespaceURI:String?,qualifiedName:String?){
        guard name=="item" else{field="";return};defer{inItem=false;field=""}
        let title=GalleryRules.visibleText(values["title"] ?? ""),link=(values["link"] ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
        let f=DateFormatter();f.locale=Locale(identifier:"en_US_POSIX");f.dateFormat="EEE, dd MMM yyyy HH:mm:ss Z"
        guard items.count<100,!title.isEmpty,title.count<=2000,let url=GalleryRules.safeURL(link),let date=f.date(from:(values["pubDate"] ?? "").trimmingCharacters(in:.whitespacesAndNewlines)) else{return}
        let body=values["content:encoded"] ?? values["description"] ?? ""
        items.append(GalleryItem(title:title,link:url.absoluteString,date:date,imageURL:GalleryRules.firstImage(body),ningning:GalleryRules.isNingning(title+" "+GalleryRules.visibleText(body))))
    }
}
// Per-request bounded streaming; no cookies/credentials/cache, redirects or image prefetch.
final class GalleryFetch:NSObject,URLSessionDataDelegate {
    private var data=Data();private let cap:Int;private let image:Bool;private var done=false
    private var completion:((Result<Data,Error>)->Void)?;private var session:URLSession?;private var task:URLSessionDataTask?
    init(url:URL,cap:Int,image:Bool,completion:@escaping(Result<Data,Error>)->Void){
        self.cap=cap;self.image=image;self.completion=completion;super.init()
        let c=URLSessionConfiguration.ephemeral;c.httpCookieStorage=nil;c.urlCredentialStorage=nil;c.urlCache=nil;c.requestCachePolicy = .reloadIgnoringLocalCacheData;c.timeoutIntervalForRequest=20;c.timeoutIntervalForResource=30
        session=URLSession(configuration:c,delegate:self,delegateQueue:nil);task=session!.dataTask(with:url);task!.resume()
    }
    func cancel(){task?.cancel();finish(.failure(NSError(domain:"Gallery",code:-999)))}
    private func finish(_ result:Result<Data,Error>){guard !done else{return};done=true;let callback=completion;completion=nil;session?.invalidateAndCancel();session=nil;DispatchQueue.main.async{callback?(result)}}
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void){completionHandler(nil)}
    func urlSession(_ session:URLSession,dataTask:URLSessionDataTask,didReceive response:URLResponse,completionHandler:@escaping(URLSession.ResponseDisposition)->Void){
        guard let http=response as? HTTPURLResponse,http.statusCode==200,response.expectedContentLength<=Int64(cap),!image || ["image/jpeg","image/png","image/webp"].contains(response.mimeType?.lowercased() ?? "") else{completionHandler(.cancel);finish(.failure(NSError(domain:"Gallery",code:3)));return};completionHandler(.allow)
    }
    func urlSession(_ session:URLSession,dataTask:URLSessionDataTask,didReceive chunk:Data){guard data.count+chunk.count<=cap else{finish(.failure(NSError(domain:"Gallery",code:4)));return};data.append(chunk)}
    func urlSession(_ session:URLSession,task:URLSessionTask,didCompleteWithError error:Error?){if let error=error{finish(.failure(error))}else{finish(.success(data))}}
}
struct GalleryPoster:Codable,Equatable {var item:GalleryItem;var filename:String;var addedAt:Date}
struct GalleryCache:Codable {var posters:[GalleryPoster]=[];var items:[GalleryItem]=[];var fetchedAt:Date?;var lastAttempt:Date?;var lastFailure:Date?;var failures:[String:Date]?;var checks:[String:Date]?;var seen:[String]?}
enum GalleryGlobalParser {
    static func match(_ pattern:String,_ text:String)throws->String {
        let regex=try NSRegularExpression(pattern:pattern);let results=regex.matches(in:text,range:NSRange(text.startIndex...,in:text))
        let values=Set(results.compactMap{m in Range(m.range(at:1),in:text).map{String(text[$0])}})
        guard values.count==1,let value=values.first else{throw NSError(domain:"GalleryGlobal",code:1)};return value
    }
    static func rootScript(_ html:String)throws->URL {
        let path=try match(#"<script\b[^>]*\bsrc=["'](/assets/index-[A-Za-z0-9_-]+\.js)["'][^>]*>"#,html)
        return URL(string:"https://aespa.com"+path)!
    }
    static func viewScript(_ root:String)throws->URL {
        let name=try match(#"import\([`"']\./(LemonadeView-[A-Za-z0-9_-]+\.js)[`"']\)"#,root)
        return URL(string:"https://aespa.com/assets/"+name)!
    }
    static func items(_ script:String)throws->[GalleryItem] {
        guard script.contains("m=`/assets/lemonade/`"),script.contains("he=`${m}slides_a/`"),script.contains("`${he}${e.dir}/${e.sub}(${n+1})${e.file}.jpg`") else{throw NSError(domain:"GalleryGlobal",code:2)}
        let group=try match(#"ge=\[(.*?)\]\.map\(e=>\(\{name:e\.name,slides:Array\.from\(\{length:e\.count\}"#,script)
        var result:[GalleryItem]=[]
        for (name,dir,file,maxCount) in [("aespa","0_aespa","aespa-lemonade",3),("NINGNING","4_ningning","ningning-lemonade",7)] {
            let declaration="{name:`\(name)`,dir:`\(dir)`,file:`\(file)`,count:\(maxCount),sub:``}"
            guard group.contains(declaration) else{throw NSError(domain:"GalleryGlobal",code:3)}
            for n in 1...min(3,maxCount) {
                let raw="https://aespa.com/assets/lemonade/slides_a/\(dir)/(\(n))\(file).jpg"
                guard let image=GalleryRules.safeURL(raw,image:true) else{throw NSError(domain:"GalleryGlobal",code:4)}
                result.append(GalleryItem(title:"\(name) · LEMONADE 官方海报 \(n)",link:"https://aespa.com/",date:nil,imageURL:image.absoluteString,ningning:name=="NINGNING"))
            }
        };return result
    }
}
enum GalleryQueue {
    static let limit=10
    static func filename(_ url:String)->String {SHA256.hash(data:Data(url.utf8)).map{String(format:"%02x",$0)}.joined()+"."+(URL(string:url)?.pathExtension.lowercased() ?? "img")}
    static func valid(_ poster:GalleryPoster)->Bool {guard let raw=poster.item.imageURL,GalleryRules.safeURL(raw,image:true) != nil,GalleryRules.safeURL(poster.item.link) != nil else{return false};return poster.filename==filename(raw)}
    static func adding(_ poster:GalleryPoster,to queue:[GalleryPoster])->[GalleryPoster] {
        guard valid(poster),!queue.contains(where:{$0.item.imageURL==poster.item.imageURL}) else{return queue}
        return Array((queue+[poster]).sorted{$0.addedAt == $1.addedAt ? $0.filename<$1.filename:$0.addedAt<$1.addedAt}.suffix(limit))
    }
    static func imageValid(_ data:Data)->Bool {guard data.count<=8_000_000,let rep=NSBitmapImageRep(data:data),rep.pixelsWide>0,rep.pixelsHigh>0,rep.pixelsWide<=6000,rep.pixelsHigh<=6000,rep.pixelsWide*rep.pixelsHigh<=36_000_000 else{return false};return true}
}
struct GalleryDeck {
    static let seconds:TimeInterval=3
    static let fade:TimeInterval=0.3
    var remaining:[String]=[];var previous:String?
    mutating func next(_ names:[String])->String? {
        guard !names.isEmpty else{remaining=[];previous=nil;return nil}
        remaining.removeAll{!names.contains($0)}
        if remaining.isEmpty {remaining=names.shuffled();if remaining.count>1,remaining.last==previous{remaining.swapAt(0,remaining.count-1)}}
        let next=remaining.removeLast();previous=next;return next
    }
}
final class GalleryStore {
    private(set) var cache=GalleryCache();let root:URL
    var status="尚未检查日本官网 RSS";var onChange:(()->Void)?
    private var fetch:GalleryFetch?;private var busy=false
    init(root:URL=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/imnotorange-pet/aespa-gallery")){
        self.root=root
        if let d=try? Data(contentsOf:root.appendingPathComponent("state.json")),d.count<=1_000_000,let c=try? JSONDecoder().decode(GalleryCache.self,from:d),c.posters.count<=10,(c.seen?.count ?? 0)<=10000,(c.seen ?? []).allSatisfy({$0.range(of:#"^[0-9a-f]{64}\.(jpg|jpeg|png|webp)$"#,options:.regularExpression) != nil}),c.posters.allSatisfy(GalleryQueue.valid),c.items.count<=100,c.items.allSatisfy({GalleryRules.safeURL($0.link) != nil}){cache=c;cache.posters.removeAll{!FileManager.default.fileExists(atPath:imageFile($0).path)};status="显示本机个人海报缓存"}
        cleanupOrphans()
    }
    private func cleanupOrphans(){
        let directory=root.appendingPathComponent("posters",isDirectory:true)
        guard let rootAttributes=try? FileManager.default.attributesOfItem(atPath:root.path),rootAttributes[.type] as? FileAttributeType == .typeDirectory,
              let attributes=try? FileManager.default.attributesOfItem(atPath:directory.path),attributes[.type] as? FileAttributeType == .typeDirectory,
              let files=try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil) else{return}
        let keep=Set(cache.posters.map{$0.filename})
        for file in files where !keep.contains(file.lastPathComponent) && file.lastPathComponent.range(of:#"^[0-9a-f]{64}\.(jpg|jpeg|png|webp)$"#,options:.regularExpression) != nil {
            if let attributes=try? FileManager.default.attributesOfItem(atPath:file.path),attributes[.type] as? FileAttributeType == .typeRegular {try? FileManager.default.removeItem(at:file)}
        }
    }
    func imageFile(_ poster:GalleryPoster)->URL {root.appendingPathComponent("posters",isDirectory:true).appendingPathComponent(poster.filename)}
    private func save()throws {try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);try JSONEncoder().encode(cache).write(to:root.appendingPathComponent("state.json"),options:.atomic)}
    @discardableResult func store(_ data:Data,item:GalleryItem,now:Date=Date())throws->Bool {
        guard GalleryQueue.imageValid(data),let imageURL=item.imageURL,GalleryRules.safeURL(imageURL,image:true) != nil else{throw NSError(domain:"Gallery",code:5)}
        let poster=GalleryPoster(item:item,filename:GalleryQueue.filename(imageURL),addedAt:now),old=cache.posters
        let next=GalleryQueue.adding(poster,to:old);guard next != old else{return false}
        try FileManager.default.createDirectory(at:root.appendingPathComponent("posters"),withIntermediateDirectories:true)
        let file=imageFile(poster);try data.write(to:file,options:.atomic);cache.posters=next
        let oldSeen=cache.seen;var seen=Set(cache.seen ?? []);seen.insert(poster.filename);cache.seen=seen.sorted()
        do{try save()}catch{cache.posters=old;cache.seen=oldSeen;if !old.contains(where:{$0.filename==poster.filename}){try? FileManager.default.removeItem(at:file)};throw error}
        // Only hash-validated files belonging to this reader's private queue are evicted.
        for removed in old where !next.contains(where:{$0.filename==removed.filename}) && GalleryQueue.valid(removed){try? FileManager.default.removeItem(at:imageFile(removed))}
        return true
    }
    private var sourceStatus:[String:String]=[:]
    private func announce(){status="JP："+(sourceStatus["jp"] ?? "待检查")+"；全球："+(sourceStatus["global"] ?? "待检查");onChange?()}
    func check(){guard !busy else{return};busy=true;checkSource("jp")}
    private func checkSource(_ source:String){
        guard GalleryRules.due(cache.failures?[source]) else{sourceStatus[source]="失败退避中，保留缓存";advance(source);return}
        cache.lastAttempt=Date()
        do{try save()}catch{sourceStatus[source]="无法保存检查状态，未请求";advance(source);return}
        sourceStatus[source]="正在检查";announce()
        if source=="jp" {
            fetch=GalleryFetch(url:GalleryRules.feed,cap:1_000_000,image:false){[weak self] result in
                guard let self=self else{return};self.fetch=nil
                do{self.accept(try GalleryFeedParser.parse(result.get()),source:source)}catch{self.finishSource(source,failed:true)}
            }
        }else{
            fetchText(URL(string:"https://aespa.com/")!){[weak self] html in
                guard let self=self else{return}
                do{let root=try GalleryGlobalParser.rootScript(html.get());self.fetchText(root){[weak self] script in
                    guard let self=self else{return}
                    do{let view=try GalleryGlobalParser.viewScript(script.get());self.fetchText(view){[weak self] code in
                        guard let self=self else{return}
                        do{self.accept(try GalleryGlobalParser.items(code.get()),source:source)}catch{self.finishSource(source,failed:true)}
                    }}catch{self.finishSource(source,failed:true)}
                }}catch{self.finishSource(source,failed:true)}
            }
        }
    }
    private func fetchText(_ url:URL,completion:@escaping(Result<String,Error>)->Void){
        fetch=GalleryFetch(url:url,cap:1_000_000,image:false){[weak self] result in self?.fetch=nil;completion(result.flatMap{data in guard let text=String(data:data,encoding:.utf8) else{return .failure(NSError(domain:"Gallery",code:8))};return .success(text)})}
    }
    private func accept(_ items:[GalleryItem],source:String){
        let host=source=="jp" ? "aespa-official.jp":"aespa.com"
        cache.items.removeAll{URL(string:$0.link)?.host==host};cache.items+=items;cache.items=Array(cache.items.suffix(100));cache.fetchedAt=Date();var checks=cache.checks ?? [:];checks[source]=Date();cache.checks=checks
        do{try save()}catch{finishSource(source,failed:true);return}
        var known=Set(cache.seen ?? []);known.formUnion(cache.posters.map{$0.filename})
        let new=items.filter{item in guard let raw=item.imageURL else{return false};return known.insert(GalleryQueue.filename(raw)).inserted}.prefix(10)
        download(Array(new).sorted{($0.date ?? .distantPast)<($1.date ?? .distantPast)},source:source,failed:false)
    }
    private func download(_ pending:[GalleryItem],source:String,failed:Bool){
        guard let item=pending.first,let raw=item.imageURL,let url=GalleryRules.safeURL(raw,image:true) else{finishSource(source,failed:failed);return}
        sourceStatus[source]="缓存可信新图（总共≤10张）";announce()
        fetch=GalleryFetch(url:url,cap:8_000_000,image:true){[weak self] result in
            guard let self=self else{return};self.fetch=nil;var bad=failed
            do{_ = try self.store(result.get(),item:item)}catch{bad=true}
            self.onChange?();self.download(Array(pending.dropFirst()),source:source,failed:bad)
        }
    }
    private func finishSource(_ source:String,failed:Bool){
        var failures=cache.failures ?? [:];if failed{failures[source]=Date()}else{failures.removeValue(forKey:source)};cache.failures=failures
        do{try save()}catch{sourceStatus[source]="缓存保存失败";advance(source);return}
        sourceStatus[source]=failed ? "部分失败，退避1小时" : "本次检查完成";advance(source)
    }
    private func advance(_ source:String){announce();if source=="jp"{checkSource("global")}else{busy=false}}

}
final class GalleryController:NSObject {
    let owner:NSWindow;let panel:ChatPanel;let store=GalleryStore()
    let image=NSImageView();let heading=NSTextField(wrappingLabelWithString:"日本官网海报")
    let open=NSButton(title:"打开当前海报原文 ↗",target:nil,action:nil)
    let filter=NSSegmentedControl(labels:["Aespa","of course NingNing"],trackingMode:.selectOne,target:nil,action:nil)
    var selected:GalleryPoster?;var deck=GalleryDeck();var timer:Timer?;var transition=UUID()
    var posters:[GalleryPoster]{store.cache.posters.filter{filter.selectedSegment==0 || $0.item.ningning}}
    init(owner:NSWindow){
        self.owner=owner;panel=ChatPanel(contentRect:NSRect(x:0,y:0,width:480,height:650),styleMask:[.borderless],backing:.buffered,defer:false);super.init()
        panel.title="Aespa";panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=true;panel.level = .floating;panel.hidesOnDeactivate=false;panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
        let content=DragBackgroundView(frame:NSRect(x:0,y:0,width:480,height:650))
        if #available(macOS 26,*){let glass=NSGlassEffectView(frame:content.bounds);glass.cornerRadius=26;glass.contentView=content;panel.contentView=glass}else{let glass=NSVisualEffectView(frame:content.bounds);glass.material = .popover;glass.state = .active;glass.addSubview(content);panel.contentView=glass}
        let label=NSTextField(labelWithString:"Be My ae");label.font=NSFont(name:"SnellRoundhand-Bold",size:29) ?? NSFont(name:"SnellRoundhand",size:29) ?? .systemFont(ofSize:27,weight:.light);label.alignment = .center;label.frame=NSRect(x:55,y:596,width:370,height:43);content.addSubview(label)
        let close=NSButton(title:"×",target:self,action:#selector(closePanel));close.frame=NSRect(x:430,y:603,width:28,height:28);content.addSubview(close)
        filter.font=NSFont(name:"SnellRoundhand",size:19) ?? .systemFont(ofSize:17,weight:.light);filter.setWidth(100,forSegment:0);filter.setWidth(310,forSegment:1);filter.selectedSegment=0;filter.frame=NSRect(x:28,y:556,width:424,height:30);filter.target=self;filter.action=#selector(filterChanged);content.addSubview(filter)
        image.frame=NSRect(x:24,y:135,width:432,height:408);image.imageScaling = .scaleProportionallyUpOrDown;content.addSubview(image)
        heading.frame=NSRect(x:28,y:78,width:424,height:50);heading.font = .systemFont(ofSize:12,weight:.semibold);heading.maximumNumberOfLines=3;content.addSubview(heading)
        open.frame=NSRect(x:245,y:26,width:205,height:28);open.target=self;open.action=#selector(openArticle);open.isEnabled=false;content.addSubview(open)
        let official=NSButton(title:"aespa.com 官方网站 ↗",target:self,action:#selector(openOfficial));official.frame=NSRect(x:28,y:26,width:200,height:28);content.addSubview(official)
        store.onChange={[weak self] in self?.refresh()};refresh()
    }
    func start(){store.check()}
    func show(){let s=(owner.screen ?? NSScreen.main)!.visibleFrame;panel.setFrameOrigin(NSPoint(x:max(s.minX,min(owner.frame.midX-240,s.maxX-480)),y:max(s.minY,min(owner.frame.maxY-8,s.maxY-650))));panel.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);refresh();nextSlide(animated:false);timer?.invalidate();timer=Timer.scheduledTimer(withTimeInterval:GalleryDeck.seconds,repeats:true){[weak self]_ in self?.nextSlide(animated:true)};RunLoop.main.add(timer!,forMode:.common)}
    @objc func closePanel(){transition=UUID();timer?.invalidate();timer=nil;image.image=nil;selected=nil;panel.orderOut(nil)}
    @objc func openOfficial(){NSWorkspace.shared.open(URL(string:"https://aespa.com/")!)}
    @objc func openArticle(){if let item=selected?.item,let u=GalleryRules.safeURL(item.link){NSWorkspace.shared.open(u)}}
    @objc func filterChanged(){deck=GalleryDeck();selected=nil;nextSlide(animated:false)}
    func refresh(){
        if panel.isVisible,selected==nil{nextSlide(animated:false)}
    }
    func nextSlide(animated:Bool){
        let available=posters;transition=UUID();let token=transition
        guard let name=deck.next(available.map{$0.filename}),let poster=available.first(where:{$0.filename==name}) else{
            image.image=nil;selected=nil;open.isEnabled=false;heading.stringValue=filter.selectedSegment==1 ? "当前官网条目暂无宁宁官方标注/文案匹配海报" : "暂无可用海报";return
        }
        let apply={ [weak self] in
            guard let self=self,self.transition==token else{return}
            self.selected=poster;self.image.image=NSImage(contentsOf:self.store.imageFile(poster));self.open.isEnabled=true;self.heading.stringValue=poster.item.title
            self.image.alphaValue=animated ? 0:1
            if animated {NSAnimationContext.runAnimationGroup{context in context.duration=GalleryDeck.fade;self.image.animator().alphaValue=1}}
        }
        if animated,image.image != nil{NSAnimationContext.runAnimationGroup({context in context.duration=GalleryDeck.fade;image.animator().alphaValue=0},completionHandler:apply)}else{apply()}
    }
}
func gallerySelfTest(){
    precondition(GalleryRules.safeURL("https://aespa-official.jp/news/test/") != nil)
    for url in ["http://aespa-official.jp/news/x/","https://aespa-official.jp.evil.test/news/x/","https://u:p@aespa-official.jp/news/x/","https://aespa-official.jp:443/news/x/","https://aespa-official.jp/news/%2e%2e/x","file:///tmp/x"]{precondition(GalleryRules.safeURL(url)==nil)}
    precondition(GalleryRules.firstImage("<img src='https://evil.test/x.jpg'><img src=\"https://aespa-official.jp/aspect/wp-content/uploads/a.webp\">")=="https://aespa-official.jp/aspect/wp-content/uploads/a.webp")
    precondition(GalleryRules.firstImage("<img data-src='https://aespa-official.jp/aspect/wp-content/uploads/a.jpg'>")==nil)
    precondition(GalleryRules.isNingning("NingNing 宁艺卓 ニンニン 닝닝"));precondition(!GalleryRules.isNingning(GalleryRules.visibleText("<img alt='Ningning'><script>Ningning</script>aespa")))
    let now=Date();precondition(GalleryRules.due(nil,now:now));precondition(!GalleryRules.due(now,now:now.addingTimeInterval(3599)));precondition(GalleryRules.due(now,now:now.addingTimeInterval(3600)));precondition(!GalleryRules.due(now,now:now.addingTimeInterval(-10)))
    precondition((try? GalleryFeedParser.parse(Data("<!DOCTYPE rss [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><rss>&x;</rss>".utf8)))==nil)
    let fixture="<rss><channel><item><title>old</title><link>https://aespa-official.jp/news/old/</link><pubDate>Sun, 15 Nov 2026 00:00:00 +0000</pubDate></item><item><title>Ningning</title><link>https://aespa-official.jp/news/new/</link><pubDate>Mon, 16 Nov 2026 00:00:00 +0000</pubDate></item></channel></rss>"
    let parsed=try! GalleryFeedParser.parse(Data(fixture.utf8));precondition(parsed.count==2 && parsed.first!.ningning && parsed.first!.title=="Ningning")
    var queue:[GalleryPoster]=[]
    for i in 0..<12 {let raw="https://aespa-official.jp/aspect/wp-content/uploads/\(i).png";let item=GalleryItem(title:"Test",link:"https://aespa-official.jp/news/\(i)/",date:Date(timeIntervalSince1970:Double(i)),imageURL:raw,ningning:false);queue=GalleryQueue.adding(GalleryPoster(item:item,filename:GalleryQueue.filename(raw),addedAt:Date(timeIntervalSince1970:Double(i))),to:queue)}
    precondition(queue.count==10 && queue.first!.item.date==Date(timeIntervalSince1970:2))
    precondition(GalleryQueue.adding(queue[0],to:queue)==queue)
    var unsafe=queue[0];unsafe.filename="../../escape.png";precondition(!GalleryQueue.valid(unsafe))
    var deck=GalleryDeck();let names=queue.map{$0.filename};var cycle=Set<String>();for _ in 0..<10{cycle.insert(deck.next(names)!)};precondition(cycle.count==10);let last=deck.previous;precondition(deck.next(names) != last);precondition(GalleryDeck.seconds==3 && GalleryDeck.fade>0 && GalleryDeck.fade<GalleryDeck.seconds)
    precondition(!GalleryQueue.imageValid(Data("not an image".utf8)))
    let space=CGColorSpace(name:CGColorSpace.sRGB)!;let context=CGContext(data:nil,width:4,height:4,bitsPerComponent:8,bytesPerRow:16,space:space,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!;let bytes=NSBitmapImageRep(cgImage:context.makeImage()!).representation(using:.png,properties:[:])!
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("gallery-test-"+UUID().uuidString);defer{try? FileManager.default.removeItem(at:directory)}
    let store=GalleryStore(root:directory);try! store.store(bytes,item:queue[0].item);precondition(try! Data(contentsOf:store.imageFile(store.cache.posters[0]))==bytes);let reload=GalleryStore(root:directory);precondition(reload.cache.posters.count==1)
    let globalFixture="m=`/assets/lemonade/`,he=`${m}slides_a/`,ge=[{name:`aespa`,dir:`0_aespa`,file:`aespa-lemonade`,count:3,sub:``},{name:`NINGNING`,dir:`4_ningning`,file:`ningning-lemonade`,count:7,sub:``}].map(e=>({name:e.name,slides:Array.from({length:e.count},(t,n)=>`${he}${e.dir}/${e.sub}(${n+1})${e.file}.jpg`)}))"
    let global=try! GalleryGlobalParser.items(globalFixture);precondition(global.count==6 && global.filter{$0.ningning}.count==3 && global.allSatisfy{$0.date==nil})
    precondition((try? GalleryGlobalParser.items(globalFixture.replacingOccurrences(of:"slides_a/",with:"other/")))==nil)
    // More than ten successful sources retain hashes even when their bytes are evicted.
    for i in 0..<12 {let raw="https://aespa-official.jp/aspect/wp-content/uploads/ledger-\(i).png";let item=GalleryItem(title:"Test",link:"https://aespa-official.jp/news/ledger-\(i)/",date:nil,imageURL:raw,ningning:false);try! store.store(bytes,item:item,now:Date(timeIntervalSince1970:Double(i)))}
    let again=GalleryStore(root:directory);precondition(again.cache.posters.count==10 && (again.cache.seen?.count ?? 0)==13)
    let oldHash=GalleryQueue.filename("https://aespa-official.jp/aspect/wp-content/uploads/ledger-0.png");precondition(again.cache.seen!.contains(oldHash) && !again.cache.posters.contains{$0.filename==oldHash})
    let orphan=directory.appendingPathComponent("posters/"+String(repeating:"a",count:64)+".png")
    let unrelated=directory.appendingPathComponent("posters/personal-note.txt")
    try! bytes.write(to:orphan);try! Data("keep".utf8).write(to:unrelated);_ = GalleryStore(root:directory)
    precondition(!FileManager.default.fileExists(atPath:orphan.path) && FileManager.default.fileExists(atPath:unrelated.path))
    print("PASS: orphan hash-image cleanup preserves unrelated files")
    print("PASS: global declared-template parsing/date-nil, source URL dedupe and cross-start eviction ledger")
    print("PASS: Aespa XML/entities, trusted URLs, text-only filter, sorting, failure backoff, 10-image dedupe/eviction, random cycle/3s/fade, hashed paths and original-byte persistence")
}
