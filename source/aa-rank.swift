import Foundation
import Security
import LocalAuthentication

enum AAKeyStore {
    private static var cachedKey:String?
    private(set) static var lastStatus:OSStatus=errSecSuccess
    static let directory=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/imnotorange-pet/private",isDirectory:true)
    static var file:URL {directory.appendingPathComponent("aa-api-key")}
    static var accessMessage:String {"本机 AA 凭据缺失或权限不正确，请联系配置者；不会弹出密码框。"}
    static func load() -> String? {
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
struct AAPage {
    let version:String;let page:Int;let hasMore:Bool;let rows:[[String]]
    static func parse(_ data:Data,expectedPage:Int)throws->AAPage {
        guard data.count<=4000000,let root=try JSONSerialization.jsonObject(with:data) as? [String:Any],let version=root["intelligence_index_version"] as? NSNumber,let pagination=root["pagination"] as? [String:Any],let page=pagination["page"] as? Int,page==expectedPage,let hasMore=pagination["has_more"] as? Bool,let items=root["data"] as? [[String:Any]],!items.isEmpty,items.count<=1000 else{throw AIRankError.invalid}
        var rows=[[String]]()
        for item in items {
            guard let name=item["name"] as? String,!name.isEmpty,name.count<=200,let creator=item["model_creator"] as? [String:Any],let maker=creator["name"] as? String,maker.count<=200,let evaluations=item["evaluations"] as? [String:Any] else{throw AIRankError.invalid}
            let value=evaluations["artificial_analysis_intelligence_index"]
            let score:String
            if value==nil || value is NSNull {score="—"}
            else if let n=value as? NSNumber,n.doubleValue.isFinite {score=String(format:"%.1f",n.doubleValue)}else{throw AIRankError.invalid}
            rows.append([name,score,maker])
        }
        return AAPage(version:version.stringValue,page:page,hasMore:hasMore,rows:rows)
    }
}
final class AARankStore:NSObject,URLSessionTaskDelegate {
    var snapshot:AIRankSnapshot?
    var status="待配置专用数据API key；未发送请求"
    var onChange:(()->Void)?
    private var started=false;private var busy=false
    private let cache=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("imnotorange-pet/ai-rank-aa.json")
    private lazy var session:URLSession={let c=URLSessionConfiguration.ephemeral;c.timeoutIntervalForRequest=20;c.timeoutIntervalForResource=35;c.httpCookieStorage=nil;c.urlCredentialStorage=nil;c.urlCache=nil;return URLSession(configuration:c,delegate:self,delegateQueue:nil)}()
    override init(){super.init();if let d=try? Data(contentsOf:cache),d.count<1048576,let v=try? JSONDecoder().decode(AIRankSnapshot.self,from:d),v.columns==["模型","Intelligence Index","厂商"],v.rows.allSatisfy({$0.count==3}){snapshot=v;status="上次成功缓存，尚未进行本次检查"}}
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void){completionHandler(nil)}
    func updateOnce(reset:Bool=false){guard !busy else{return};if reset{started=false};guard !started else{return};started=true;guard let key=AAKeyStore.load() else {status="本机 AA 凭据缺失或权限不正确；本次未请求API。点击“配置 AA key”在本机输入";onChange?();return};update(key:key)}
    func update(key:String){
        guard !busy else{return};busy=true;status="正在读取官方免费API（单次分页更新，无轮询）…";onChange?()
        Task {
            do {
                var rows=[[String]](),version="",complete=false
                for page in 1...10 {
                    var request=URLRequest(url:URL(string:"https://artificialanalysis.ai/api/v2/language/models/free?page=\(page)")!);request.setValue(key,forHTTPHeaderField:"x-api-key")
                    let (data,response)=try await session.data(for:request)
                    guard let http=response as? HTTPURLResponse else{throw AIRankError.invalid};guard http.statusCode==200 else{throw AIRankError.http(http.statusCode)}
                    let parsed=try AAPage.parse(data,expectedPage:page)
                    if version.isEmpty{version=parsed.version}else if version != parsed.version{throw AIRankError.invalid}
                    rows+=parsed.rows
                    if !parsed.hasMore{complete=true;break}
                }
                guard complete,!rows.isEmpty else{throw AIRankError.invalid}
                rows.sort{(Double($0[1]) ?? -.infinity)>(Double($1[1]) ?? -.infinity)}
                let next=AIRankSnapshot(fetchedAt:Date(),release:version,source:"https://artificialanalysis.ai/api/v2/language/models/free",columns:["模型","Intelligence Index","厂商"],rows:rows)
                var persisted=true
                do{try FileManager.default.createDirectory(at:cache.deletingLastPathComponent(),withIntermediateDirectories:true);try JSONEncoder().encode(next).write(to:cache,options:.atomic)}catch{persisted=false}
                let saved=persisted
                await MainActor.run{self.snapshot=next;self.status=saved ? "官方API更新成功；按Intelligence Index降序" : "更新成功，但缓存保存失败";self.busy=false;self.onChange?()}
            }catch {
                let detail:String
                if case AIRankError.http(let code)=error {detail=[401:"Key无效",403:"此key无访问权限",429:"达到配额，不自动重试"][code] ?? "HTTP \(code)"}else{detail="网络或格式错误"}
                await MainActor.run{self.status="更新失败（\(detail)）"+(self.snapshot == nil ? "，无可用缓存" : "，显示上次成功缓存，非实时");self.busy=false;self.onChange?()}
            }
        }
    }
}
