import AppKit

// Fixed shell program; PID, bundle path and executable are separate arguments, never interpolated.
enum PetRestart {
    static let waitScript = """
    case "$1" in ''|*[!0-9]*|0|1) exit 2;; esac
    [ -d "$2" ] || exit 3
    count=0
    while kill -0 "$1" 2>/dev/null; do
      [ "$count" -lt "$4" ] || exit 4
      /bin/sleep 0.1
      count=$((count + 1))
    done
    exec "$3" -a "$2"
    """
    static func helper(pid:pid_t,bundle:URL,launcher:String="/usr/bin/open",polls:Int=300)->Process {
        let process=Process();process.executableURL=URL(fileURLWithPath:"/bin/sh")
        process.arguments=["-c",waitScript,"pet-restart",String(pid),bundle.path,launcher,String(polls)]
        process.standardInput=FileHandle.nullDevice;process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.nullDevice
        return process
    }
    static func start() throws {
        let bundle=Bundle.main.bundleURL
        guard bundle.pathExtension=="app",FileManager.default.isExecutableFile(atPath:Bundle.main.executableURL?.path ?? "") else {throw NSError(domain:"PetRestart",code:1)}
        try helper(pid:ProcessInfo.processInfo.processIdentifier,bundle:bundle).run()
    }
}
func restartSelfTest() {
    let fm=FileManager.default;let dir=fm.temporaryDirectory.appendingPathComponent("pet-restart-test-"+UUID().uuidString)
    try! fm.createDirectory(at:dir,withIntermediateDirectories:true);defer{try? fm.removeItem(at:dir)}
    let bundle=dir.appendingPathComponent("中文 name ' $(literal).app");try! fm.createDirectory(at:bundle,withIntermediateDirectories:true)
    let marker=dir.appendingPathComponent("result");let mock=dir.appendingPathComponent("mock-launcher")
    // The mock records its two argv strings only. It never opens an app.
    try! Data("#!/bin/sh\nprintf '%s\\n' \"$1\" \"$2\" > \"$(dirname \"$0\")/result\"\n".utf8).write(to:mock)
    try! fm.setAttributes([.posixPermissions:0o700],ofItemAtPath:mock.path)
    let sleeper=Process();sleeper.executableURL=URL(fileURLWithPath:"/bin/sleep");sleeper.arguments=["0.5"];try! sleeper.run()
    let waiter=PetRestart.helper(pid:sleeper.processIdentifier,bundle:bundle,launcher:mock.path,polls:50);try! waiter.run()
    Thread.sleep(forTimeInterval:0.1);precondition(!fm.fileExists(atPath:marker.path));sleeper.waitUntilExit();waiter.waitUntilExit()
    precondition(waiter.terminationStatus==0);precondition(try! String(contentsOf:marker)=="-a\n"+bundle.path+"\n")
    try! fm.removeItem(at:marker)
    let timeout=PetRestart.helper(pid:ProcessInfo.processInfo.processIdentifier,bundle:bundle,launcher:mock.path,polls:1);try! timeout.run();timeout.waitUntilExit()
    precondition(timeout.terminationStatus==4 && !fm.fileExists(atPath:marker.path))
    print("PASS: restart waits for old PID, literal-path argv, timeout abort; mock only, no app restarted")
}
