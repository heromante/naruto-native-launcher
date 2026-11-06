import Foundation
import CryptoKit
import Darwin

enum LauncherError: Error, LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
func require(_ condition: @autoclosure () throws -> Bool, _ text: String) throws {
    if try !condition() { throw LauncherError.message(text) }
}
func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
func fileSHA256(_ url: URL) throws -> String {
    let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
    return try sha256Stream(file)
}
private func sha256Stream(_ file: FileHandle) throws -> String {
    try file.seek(toOffset: 0)
    var hash = SHA256()
    while let data = try file.read(upToCount: 4 * 1024 * 1024), !data.isEmpty { hash.update(data: data) }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
}
extension Data {
    func le32(_ at: Int) -> UInt32 { (0..<4).reduce(UInt32(0)) { $0 | UInt32(self[at + $1]) << ($1 * 8) } }
    func be32(_ at: Int) -> UInt32 { (0..<4).reduce(UInt32(0)) { ($0 << 8) | UInt32(self[at + $1]) } }
}
struct ISOEntry: Codable {
    let path: String
    let sector: UInt64
    let size: UInt64
}
final class ISOReader {
    let url: URL
    let handle: FileHandle
    let size: UInt64
    let volume: String
    private let initialStat: stat
    private var directories = Set<UInt64>()
    private var directoryBytes: UInt64 = 0
    private var recordCount = 0
    private(set) var entries: [String: ISOEntry] = [:]
    init(_ url: URL) throws {
        self.url = url
        let fd = open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        try require(fd >= 0, "Não foi possível abrir o arquivo ISO.")
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var info = stat()
        try require(fstat(fd, &info) == 0 && info.st_mode & S_IFMT == S_IFREG,
                    "Selecione um arquivo ISO regular.")
        self.initialStat = info
        self.size = UInt64(max(info.st_size, 0))
        try require(size >= 17 * 2048 && size <= 16 * 1024 * 1024 * 1024, "Tamanho de imagem ISO inválido.")
        self.handle = file
        try handle.seek(toOffset: 16 * 2048)
        let pvd = try handle.read(upToCount: 2048) ?? Data()
        try require(pvd.count == 2048 && Array(pvd.prefix(7)) == [1,67,68,48,48,49,1], "O arquivo não é uma ISO9660 de 2048 bytes por setor.")
        self.volume = String(decoding: pvd[40..<72], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        try require(pvd.le32(80) == pvd.be32(84), "A estrutura da ISO está inconsistente.")
        try require(UInt64(pvd.le32(80)) * 2048 <= size, "A ISO está truncada.")
        try require(pvd.le32(158) == pvd.be32(162) && pvd.le32(166) == pvd.be32(170), "Diretório raiz da ISO inválido.")
        try walk(UInt64(pvd.le32(158)), UInt64(pvd.le32(166)), "", 0)
    }
    func fingerprint() throws -> String {
        let digest = try sha256Stream(handle)
        var current = stat()
        try require(lstat(url.path, &current) == 0 && current.st_mode & S_IFMT == S_IFREG &&
                    current.st_dev == initialStat.st_dev && current.st_ino == initialStat.st_ino &&
                    current.st_size == initialStat.st_size &&
                    current.st_mtimespec.tv_sec == initialStat.st_mtimespec.tv_sec &&
                    current.st_mtimespec.tv_nsec == initialStat.st_mtimespec.tv_nsec &&
                    current.st_ctimespec.tv_sec == initialStat.st_ctimespec.tv_sec &&
                    current.st_ctimespec.tv_nsec == initialStat.st_ctimespec.tv_nsec,
                    "A ISO mudou durante a leitura. Tente novamente.")
        return digest
    }
    func read(_ offset: UInt64, _ count: UInt64) throws -> Data {
        try require(count <= 16 * 1024 * 1024 && offset <= size && count <= size - offset, "Leitura fora dos limites da ISO.")
        try handle.seek(toOffset: offset)
        let data = try handle.read(upToCount: Int(count)) ?? Data()
        try require(data.count == Int(count), "Não foi possível ler a ISO por completo.")
        return data
    }
    private func walk(_ sector: UInt64, _ length: UInt64, _ prefix: String, _ depth: Int) throws {
        try require(depth <= 8 && length > 0 && length <= 4 * 1024 * 1024 &&
                    directories.insert(sector).inserted, "Diretório inválido, repetido ou cíclico na ISO.")
        directoryBytes += length
        try require(directoryBytes <= 32 * 1024 * 1024, "Diretórios da ISO excedem o limite de leitura.")
        let data = try read(sector * 2048, length)
        var offset = 0
        while offset < data.count {
            let n = Int(data[offset])
            if n == 0 { offset = (offset / 2048 + 1) * 2048; continue }
            recordCount += 1
            try require(recordCount <= 20000 && n >= 34 && n <= data.count - offset &&
                        n <= 2048 - offset % 2048, "Registro de diretório ISO inválido ou excessivo.")
            let record = Data(data[offset..<offset+n]); offset += n
            let nameLength = Int(record[32])
            try require(nameLength > 0 && nameLength <= n - 33, "Nome de arquivo ISO inválido.")
            let nameBytes = Array(record[33..<33+nameLength])
            if nameBytes == [0] || nameBytes == [1] { continue }
            try require(nameBytes.allSatisfy { $0 >= 32 && $0 < 127 }, "Nome de arquivo não suportado na ISO.")
            let name = String(bytes: nameBytes, encoding: .ascii)!.components(separatedBy: ";")[0].uppercased()
            try require(!name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\"), "Caminho inválido na ISO.")
            try require(record.le32(2) == record.be32(6) && record.le32(10) == record.be32(14), "Registro ISO com tamanhos inconsistentes.")
            try require(record[26] == 0 && record[27] == 0 && record[25] & 0x80 == 0, "Imagem ISO com arquivos fragmentados não suportada.")
            let lba = UInt64(record.le32(2)); let count = UInt64(record.le32(10))
            try require(lba * 2048 <= size && count <= size - lba * 2048, "Arquivo excede o tamanho da ISO.")
            let path = prefix + name
            try require(entries.count < 10000 && entries[path] == nil, "Diretório ISO duplicado ou excessivamente grande.")
            if record[25] & 2 != 0 { try walk(lba, count, path + "/", depth + 1) }
            else { entries[path] = ISOEntry(path: path, sector: lba, size: count) }
        }
    }
    func file(_ path: String, maximum: UInt64 = 16 * 1024 * 1024) throws -> Data {
        guard let entry = entries[path] else { throw LauncherError.message("Arquivo ausente na ISO: \(path)") }
        try require(entry.size <= maximum, "Arquivo da ISO excede o limite esperado: \(path)")
        return try read(entry.sector * 2048, entry.size)
    }
}
struct GameInspection: Codable {
    let path: String
    let bytes: UInt64
    let volume: String
    let serial: String
    let videoMode: String
    let isoSHA256: String
    let elfSHA256: String
    let elfEntry: ISOEntry
    let modificationIndicators: [String]
}
func inspectISO(_ selectedURL: URL) throws -> GameInspection {
    let url = selectedURL.resolvingSymlinksInPath().standardizedFileURL
    let image = try ISOReader(url)
    let config = String(decoding: try image.file("SYSTEM.CNF", maximum: 4096), as: UTF8.self)
    guard let line = config.components(separatedBy: .newlines).first(where: { $0.trimmingCharacters(in: .whitespaces).uppercased().hasPrefix("BOOT2") }),
          let equal = line.firstIndex(of: "=") else { throw LauncherError.message("SYSTEM.CNF não informa o jogo de PS2.") }
    let boot = line[line.index(after: equal)...].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    try require(boot.hasPrefix("CDROM0:\\"), "Caminho de inicialização de PS2 não suportado.")
    let serial = String(boot.dropFirst(8)).components(separatedBy: ";")[0]
    try require(serial.range(of: "^[A-Z]{4}_[0-9]{3}\\.[0-9]{2}$", options: .regularExpression) != nil, "Identificação de jogo inválida.")
    guard let entry = image.entries[serial] else { throw LauncherError.message("Executável informado em SYSTEM.CNF não foi encontrado.") }
    let elf = try image.file(serial)
    try require(elf.count >= 52 && Array(elf.prefix(6)) == [0x7f,69,76,70,1,1], "Executável PS2 inválido.")
    try require(elf[18] == 8 && elf[19] == 0 && elf.le32(20) == 1, "O executável não é MIPS de PS2.")
    let mode = config.components(separatedBy: .newlines).first { $0.trimmingCharacters(in: .whitespaces).uppercased().hasPrefix("VMODE") }?.components(separatedBy: "=").last?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? "AUTO"
    var indicators: [String] = []
    if image.volume.uppercased().contains("PLUS") { indicators.append("volume-plus") }
    if image.entries["PRG/TEXTBRA.BIN"] != nil { indicators.append("textbra") }
    if image.entries["PRG/MOD.BIN"] != nil { indicators.append("mod-module") }
    let digest = try image.fingerprint()
    return GameInspection(path: url.path, bytes: image.size, volume: image.volume, serial: serial, videoMode: mode, isoSHA256: digest, elfSHA256: sha256(elf), elfEntry: entry, modificationIndicators: indicators)
}
struct EngineProfile: Codable {
    let id: String
    let title: String
    let scope: String
    let isoSHA256: String
    let elfSHA256: String
    let engine: String
    let engineSHA256: String
    let libraries: [String: String]
    let videoMode: String
    let minimumMacOS: String
    let hotKernels: Bool
    let frameCounter: String?
}
struct EngineCatalog: Codable { let schema: Int; let profiles: [EngineProfile] }
func readCatalog(_ resources: URL) throws -> EngineCatalog {
    let file = resources.appendingPathComponent("engines.json")
    let catalog = try JSONDecoder().decode(EngineCatalog.self, from: Data(contentsOf: file))
    try require(catalog.schema == 1, "Catálogo de versões incompatível.")
    return catalog
}
func matchedProfile(_ game: GameInspection, _ profiles: [EngineProfile]) -> EngineProfile? {
    profiles.first { $0.isoSHA256 == game.isoSHA256 && $0.elfSHA256 == game.elfSHA256 }
}
func supportedGame(_ game: GameInspection, _ catalog: EngineCatalog) throws -> EngineProfile {
    try require(game.serial == "SLES_556.05", "Esta imagem é de outro jogo ou região. Selecione Ultimate Ninja 5 europeu (SLES-55605).")
    guard let profile = matchedProfile(game, catalog.profiles) else {
        throw LauncherError.message("Ultimate Ninja 5 europeu identificado. Esta edição ainda precisa de adaptação e validação do motor nativo. A execução não foi liberada para esta ISO.")
    }
    try require(profile.scope == "original-european" && profile.videoMode == "pal", "Este pacote precisa de um motor validado para a edição europeia PAL.")
    return profile
}
func resourceFile(_ resources: URL, _ path: String) throws -> URL {
    let root = resources.resolvingSymlinksInPath().standardizedFileURL
    let result = root.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
    try require(result.path.hasPrefix(root.path + "/"), "Caminho inválido no pacote do inicializador.")
    return result
}
struct LaunchPlan: Codable {
    let executable: String
    let arguments: [String]
    let environment: [String: String]
    let workingDirectory: String
    let log: String
    let profile: String
}
func makePlan(_ game: GameInspection, _ profile: EngineProfile, _ resources: URL, _ directory: URL, scale: Int, muted: Bool) throws -> LaunchPlan {
    try require(game.isoSHA256 == profile.isoSHA256 && game.elfSHA256 == profile.elfSHA256, "Esta ISO não corresponde ao motor selecionado.")
    try require([1,2].contains(scale), "Escolha resolução 1× ou 2×.")
    try require(profile.id.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil, "Perfil de jogo inválido.")
    let parts = profile.minimumMacOS.split(separator: ".").compactMap { Int($0) }
    try require(!parts.isEmpty, "Requisito de sistema inválido.")
    try require(ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: parts[0], minorVersion: parts.count>1 ? parts[1]:0, patchVersion: parts.count>2 ? parts[2]:0)), "Este motor requer macOS \(profile.minimumMacOS) ou posterior.")
    let engine = try resourceFile(resources, profile.engine)
    try require(try fileSHA256(engine) == profile.engineSHA256, "O motor do jogo foi alterado. Reinstale este pacote.")
    for (path, expected) in profile.libraries { try require(try fileSHA256(resourceFile(resources, path)) == expected, "Uma biblioteca do motor foi alterada.") }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let elfURL = directory.appendingPathComponent(game.serial)
    let data = try ISOReader(URL(fileURLWithPath: game.path)).file(game.serial)
    try require(sha256(data) == game.elfSHA256 && game.elfSHA256 == profile.elfSHA256, "O executável da ISO mudou. Selecione a imagem novamente.")
    let existingHash = FileManager.default.fileExists(atPath: elfURL.path) ? try fileSHA256(elfURL) : nil
    if existingHash != game.elfSHA256 { try data.write(to: elfURL, options: .atomic) }
    let log = directory.appendingPathComponent("session-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8)).log")
    // The game needs OS paths/locales, not credentials or settings of other tools.
    let allowed = Set(["HOME","TMPDIR","USER","LOGNAME","LANG","LC_ALL","LC_CTYPE","__CF_USER_TEXT_ENCODING","XDG_CACHE_HOME","XDG_DATA_HOME","XDG_RUNTIME_DIR"])
    var env = ProcessInfo.processInfo.environment.filter { allowed.contains($0.key) }
    env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
    env["PS2_SCALE"] = String(scale); env["PS2_PACING"] = "original"; env["PS2_GPU_LOW_POWER"] = "1"; env["PS2_VU_STREAM_KICK"] = "1"; env["PS2_SPEED_LOG"] = "1"
    if profile.hotKernels { env["PS2_VU_HOT_COMPILED"] = "1" }
    if let counter = profile.frameCounter {
        try require(counter.range(of: "^[0-9a-fA-F]+,[0-9a-fA-F]+$",options:.regularExpression) != nil,"Contador de desempenho inválido.")
        env["PS2_GAME_FRAME_COUNTER"] = counter
    }
    if muted { env["PS2_TEST_MUTE"] = "1" }
    let args = [elfURL.path,"--disc",game.path,"--pal","--window","--memcard",directory.appendingPathComponent("memory-card.ps2").path,"--misses",directory.appendingPathComponent("missing-code.txt").path]
    return LaunchPlan(executable: engine.path, arguments: args, environment: env, workingDirectory: directory.path, log: log.path, profile: profile.id)
}
func supportRoot() -> URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NarutoNativeLauncher", isDirectory: true)
}

func openSessionLog(_ path: String) throws -> FileHandle {
    let fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    try require(fd >= 0, "Não foi possível criar um log privado para esta sessão.")
    return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
}
