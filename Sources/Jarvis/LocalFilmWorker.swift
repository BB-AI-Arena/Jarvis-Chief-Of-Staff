import Foundation

/// Runs the checkpointed local film engine without exposing credentials to the page or job files.
/// The worker reads the unchanged jarvis-keys helper directly on this Mac.
enum LocalFilmWorker {
    // Internal dependency seam for a no-network worker fixture; production uses the monetary gate.
    static var canStart: () -> Bool = { SpendBudget.allowsUnboundedJobs }
    static func tokenBudget(seconds:Int)->Int { max(150_000,min(600,max(0,seconds))*20_000/3) }
    static func spec(brief:String,seconds:Int,artwork:[VideoArtwork.Reference],workflow:[String:Any],server:String,dark:DarkServer,project:URL,model:String,clientID:String)->[String:Any] {
        ["brief":brief,"seconds":seconds,"artwork":artwork.map { ref -> [String:Any] in
            var value:[String:Any]=["source":ref.source,"image":ref.image,"sha256":ref.sha256]
            if let role=ref.role { value["role"]=role };return value
        },"workflow":workflow,"server":server,"dark":["host":dark.host,"user":dark.user,"key":dark.key],
         "project":project.path,"model":model,"client_id":clientID,"director_system":VideoArtwork.storyboardSystem,
         "token_budget":tokenBudget(seconds:seconds),"max_grok_stills":min(10,max(1,Int(ceil(Double(seconds)/60))))]
    }
    @discardableResult static func start(spec:[String:Any],folder:URL,project:URL,script:URL,event:@escaping ([String:Any])->Void,completion:@escaping (Int32)->Void)->Process? {
        guard canStart() else { event(["type":"failed","message":SpendBudget.blocked]);completion(1);return nil }
        do {
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let data=try JSONSerialization.data(withJSONObject:spec,options:[.prettyPrinted,.sortedKeys])
            try data.write(to:folder.appendingPathComponent("job.json"),options:.atomic)
        } catch { event(["type":"failed","message":"Could not save the film job: " + error.localizedDescription]);completion(1);return nil }
        let process=Process(),pipe=Pipe()
        process.executableURL=project.appendingPathComponent(".voice/bin/python")
        process.arguments=["-B",script.path,"--job",folder.appendingPathComponent("job.json").path]
        process.currentDirectoryURL=project
        process.standardInput=FileHandle.nullDevice;process.standardOutput=pipe
        let log=folder.appendingPathComponent("worker-stderr.log")
        FileManager.default.createFile(atPath:log.path,contents:nil)
        process.standardError=try? FileHandle(forWritingTo:log)
        let activity=ProcessInfo.processInfo.beginActivity(options:[.userInitiated,.idleSystemSleepDisabled],reason:"Render the directed film on DARK and save its checkpoints")
        do { try process.run() } catch {
            ProcessInfo.processInfo.endActivity(activity)
            event(["type":"failed","message":"Could not start the film worker: " + error.localizedDescription]);completion(1);return nil
        }
        DispatchQueue.global(qos:.utility).async {
            let eventsURL=folder.appendingPathComponent("worker-events.jsonl")
            FileManager.default.createFile(atPath:eventsURL.path,contents:nil)
            let events=try? FileHandle(forWritingTo:eventsURL)
            defer { try? events?.close() }
            var buffer=Data()
            while true {
                let chunk=pipe.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                while let end=buffer.firstIndex(of:10) {
                    let line=Data(buffer.prefix(upTo:end));buffer.removeSubrange(...end)
                    try? events?.write(contentsOf:line + Data([10]))
                    if let object=try? JSONSerialization.jsonObject(with:Data(line)) as? [String:Any] { DispatchQueue.main.async { event(object) } }
                }
            }
            process.waitUntilExit()
            let status=process.terminationStatus
            DispatchQueue.main.async { ProcessInfo.processInfo.endActivity(activity);completion(status) }
        }
        return process
    }
}
