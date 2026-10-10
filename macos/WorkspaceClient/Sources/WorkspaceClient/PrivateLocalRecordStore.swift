import Foundation
import Darwin

// Descriptor-relative private record I/O shared by legacy drafts and durable mission transport intents.
struct PrivateLocalRecordStore: Sendable {
    let root: URL
    let namespace: String
    let synchronizeDirectory: @Sendable(Int32) -> Int32
    init(root: URL, namespace: String, synchronizeDirectory: @escaping @Sendable(Int32) -> Int32 = { fsync($0) }) {
        self.root = root; self.namespace = namespace; self.synchronizeDirectory = synchronizeDirectory
    }
    private func name(_ key:String) throws -> String {
        guard key.range(of:"^[0-9a-f]{64}$",options:.regularExpression) != nil else { throw AdvisoryError.invalid }
        guard ["candidate", "mission", "workset-release"].contains(namespace) else { throw AdvisoryError.invalid }
        return namespace+"-"+key+".json"
    }
    private func directory() throws -> Int32 {
        // Only the platform's fixed /tmp and /var aliases are normalized.
        var path=root.standardizedFileURL.path
        if path.hasPrefix("/tmp/") { path="/private"+path }
        if path.hasPrefix("/var/") { path="/private"+path }
        var fd=Darwin.open("/",O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
        guard fd>=0 else { throw AdvisoryError.unavailable }
        do {
            for component in path.split(separator:"/").map(String.init) {
                var next=openat(fd,component,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
                if next<0 && errno==ENOENT {
                    let created=mkdirat(fd,component,0o700)
                    guard created==0 || errno==EEXIST else { throw AdvisoryError.unavailable }
                    next=openat(fd,component,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
                }
                guard next>=0 else { throw AdvisoryError.unavailable }
                var child=stat()
                guard fstat(next,&child)==0 else { Darwin.close(next);throw AdvisoryError.unavailable }
                // Synchronize every owned child entry on retries, including entries
                // left behind by an earlier failed parent sync.
                if child.st_uid==getuid(),synchronizeDirectory(fd) != 0 {
                    Darwin.close(next);throw AdvisoryError.unavailable
                }
                Darwin.close(fd);fd=next
            }
            var info=stat()
            guard fstat(fd,&info)==0,info.st_mode & mode_t(S_IFMT)==mode_t(S_IFDIR),info.st_uid==getuid(),info.st_mode & 0o077==0 else { throw AdvisoryError.unavailable }
            return fd
        } catch { Darwin.close(fd);throw error }
    }
    func load(_ key:String) throws -> Data? {
        let file=try name(key),dir=try directory();defer{Darwin.close(dir)}
        let fd=openat(dir,file,O_RDONLY|O_NOFOLLOW|O_CLOEXEC)
        if fd<0 && errno==ENOENT { return nil }
        guard fd>=0 else { throw AdvisoryError.unavailable }
        let handle=FileHandle(fileDescriptor:fd,closeOnDealloc:true);defer{try? handle.close()}
        var info=stat()
        guard fstat(fd,&info)==0,info.st_mode & mode_t(S_IFMT)==mode_t(S_IFREG),info.st_uid==getuid(),info.st_mode & 0o077==0,info.st_size<=65536 else { throw AdvisoryError.unavailable }
        let data=try handle.read(upToCount:65537) ?? Data()
        guard data.count<=65536 else { throw AdvisoryError.invalid }
        return data
    }
    func save(_ data:Data,key:String) throws {
        let target=try name(key)
        guard data.count<=65536 else { throw AdvisoryError.state("LOCAL_CAPACITY_EXHAUSTED") }
        let dir=try directory();defer{Darwin.close(dir)}
        var info=stat()
        if fstatat(dir,target,&info,AT_SYMLINK_NOFOLLOW)==0 {
            guard info.st_mode & mode_t(S_IFMT)==mode_t(S_IFREG),info.st_uid==getuid(),info.st_mode & 0o077==0 else { throw AdvisoryError.unavailable }
        } else if errno != ENOENT { throw AdvisoryError.unavailable }
        let temporary="."+namespace+"-"+UUID().uuidString+".tmp"
        let fd=openat(dir,temporary,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0o600)
        guard fd>=0 else { throw AdvisoryError.unavailable }
        let h=FileHandle(fileDescriptor:fd,closeOnDealloc:true)
        defer { try? h.close();unlinkat(dir,temporary,0) }
        try h.write(contentsOf:data);try h.synchronize()
        guard renameat(dir,temporary,dir,target)==0,synchronizeDirectory(dir)==0 else { throw AdvisoryError.unavailable }
    }
}
