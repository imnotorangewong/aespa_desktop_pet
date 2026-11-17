import Foundation

struct ArenaPage {
    static let source="https://huggingface.co/datasets/lmarena-ai/leaderboard-dataset"
    static let columns=["名次","模型","Arena Score","置信区间","票数","机构"]
    static func parse(_ data:Data)throws->AIRankSnapshot {
        guard data.count<=2000000,let root=try JSONSerialization.jsonObject(with:data) as? [String:Any],root["partial"] as? Bool==false,let items=root["rows"] as? [[String:Any]],!items.isEmpty,items.count<=100 else{throw AIRankError.invalid}
        var rows=[[String]](),dates=Set<String>(),ranks=Set<Int>()
        let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.dateFormat="yyyy-MM-dd";formatter.isLenient=false
        for item in items {
            guard let truncated=item["truncated_cells"] as? [Any],truncated.isEmpty,let row=item["row"] as? [String:Any],row["category"] as? String=="overall",let name=row["model_name"] as? String,!name.isEmpty,name.count<=200,let org=row["organization"] as? String,org.count<=150,let score=row["rating"] as? NSNumber,let low=row["rating_lower"] as? NSNumber,let high=row["rating_upper"] as? NSNumber,let votes=row["vote_count"] as? NSNumber,let rank=row["rank"] as? NSNumber,let date=row["leaderboard_publish_date"] as? String,let parsedDate=formatter.date(from:date),formatter.string(from:parsedDate)==date else{throw AIRankError.invalid}
            let numbers=[score,low,high,votes,rank].map{$0.doubleValue}
            guard numbers.allSatisfy({$0.isFinite}),low.doubleValue<=score.doubleValue,score.doubleValue<=high.doubleValue,votes.doubleValue>=0,rank.doubleValue==Double(rank.intValue),(1...100).contains(rank.intValue) else{throw AIRankError.invalid}
            dates.insert(date);ranks.insert(rank.intValue)
            rows.append([String(rank.intValue),name,String(format:"%.1f",score.doubleValue),String(format:"%.1f–%.1f",low.doubleValue,high.doubleValue),String(format:"%.0f",votes.doubleValue),org])
        }
        guard dates.count==1,ranks.count==rows.count,ranks.min()==1,ranks.max()==rows.count else{throw AIRankError.invalid}
        rows.sort{Int($0[0])!<Int($1[0])!}
        return AIRankSnapshot(fetchedAt:Date(),release:dates.first!,source:source,columns:columns,rows:rows)
    }
}
final class ArenaRankStore:NSObject,URLSessionTaskDelegate {
    var snapshot:AIRankSnapshot?;var status="尚未检查官方开放数据集";var onChange:(()->Void)?
    private var started=false;private var busy=false
    private let cache=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("imnotorange-pet/ai-rank-arena.json")
    private lazy var session:URLSession={let c=URLSessionConfiguration.ephemeral;c.timeoutIntervalForRequest=25;c.timeoutIntervalForResource=35;c.httpCookieStorage=nil;c.urlCredentialStorage=nil;c.urlCache=nil;return URLSession(configuration:c,delegate:self,delegateQueue:nil)}()
    override init(){super.init();if let d=try? Data(contentsOf:cache),d.count<1048576,let s=try? JSONDecoder().decode(AIRankSnapshot.self,from:d),s.columns==ArenaPage.columns,s.rows.allSatisfy({$0.count==6}){snapshot=s;status="已载入上次成功缓存"}}
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void){completionHandler(nil)}
    func updateOnce(reset:Bool=false){
        guard !busy else{return};if reset{started=false};guard !started else{return};started=true;busy=true;status="正在检查Arena官方开放数据集…";onChange?()
        Task {
            do {
                var url=URLComponents(string:"https://datasets-server.huggingface.co/rows")!
                url.queryItems=[URLQueryItem(name:"dataset",value:"lmarena-ai/leaderboard-dataset"),URLQueryItem(name:"config",value:"text"),URLQueryItem(name:"split",value:"latest"),URLQueryItem(name:"offset",value:"0"),URLQueryItem(name:"length",value:"100")]
                let (data,response)=try await session.data(from:url.url!)
                guard let http=response as? HTTPURLResponse else{throw AIRankError.invalid};guard http.statusCode==200 else{throw AIRankError.http(http.statusCode)}
                let next=try ArenaPage.parse(data)
                var saved=true;do{try FileManager.default.createDirectory(at:cache.deletingLastPathComponent(),withIntermediateDirectories:true);try JSONEncoder().encode(next).write(to:cache,options:.atomic)}catch{saved=false}
                let persisted=saved
                await MainActor.run{self.snapshot=next;self.busy=false;self.status=persisted ? "官方开放快照检查成功，不保证与官网实时同步" : "快照更新成功，缓存保存失败";self.onChange?()}
            }catch{await MainActor.run{self.busy=false;self.status=self.snapshot==nil ? "官方数据集更新失败，无可用缓存" : "更新失败，显示上次成功快照，非实时";self.onChange?()}}
        }
    }
}
