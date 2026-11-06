import AppKit
import Foundation
import UniformTypeIdentifiers
import Darwin

let resourceRoot: URL = {
    if let index = CommandLine.arguments.firstIndex(of: "--resources"), index+1 < CommandLine.arguments.count { return URL(fileURLWithPath: CommandLine.arguments[index+1]) }
    return Bundle.main.resourceURL ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
}()
func printJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]
    print(String(decoding: try encoder.encode(value), as: UTF8.self))
}
func cli() -> Bool {
    let args = CommandLine.arguments
    guard let mode = args.first(where: { ["--inspect","--plan","--smoke-test"].contains($0) }), let i = args.firstIndex(of: mode), i+1 < args.count else { return false }
    do {
        if let index = args.firstIndex(of: "--video-mode") {
            try require(index + 1 < args.count && args[index + 1] == "pal", "O inicializador usa apenas a cadência PAL original.")
        }
        let game = try inspectISO(URL(fileURLWithPath: args[i+1])); let catalog = try readCatalog(resourceRoot)
        if mode == "--inspect" {
            struct Output: Encodable { let inspection: GameInspection; let matchedProfile: String?; let originalEuropeanValidated: Bool }
            let match = matchedProfile(game,catalog.profiles)
            try printJSON(Output(inspection:game,matchedProfile:match?.id,originalEuropeanValidated:match?.scope == "original-european" && match?.videoMode == "pal")); exit(0)
        }
        let profile = try supportedGame(game,catalog)
        let test = mode == "--smoke-test"
        let destination = test ? supportRoot().appendingPathComponent("Tests/"+UUID().uuidString) : supportRoot().appendingPathComponent("Games/"+profile.id)
        let plan = try makePlan(game,profile,resourceRoot,destination,scale:1,muted:true)
        if !test { try printJSON(plan); exit(0) }
        // Bounded GPU smoke test: private save folder, hidden, muted, one process.
        let lock = open(supportRoot().appendingPathComponent("game.lock").path,O_CREAT|O_RDWR,0o600)
        try require(lock >= 0 && flock(lock,LOCK_EX|LOCK_NB) == 0,"Já existe um jogo aberto neste inicializador.")
        defer { close(lock) }
        let process = Process(); process.executableURL = URL(fileURLWithPath:plan.executable)
        process.arguments = plan.arguments + ["--frames","600","--press","300:cross:2"]
        var env = plan.environment;env["PS2_TEST_WINDOW_HIDDEN"]="1";env["SDL_MAC_BACKGROUND_APP"]="1";env["SDL_WINDOW_NO_ACTIVATION_WHEN_SHOWN"]="1";process.environment=env
        process.currentDirectoryURL=URL(fileURLWithPath:plan.workingDirectory)
        let log=try openSessionLog(plan.log);defer{try?log.close()};process.standardOutput=log;process.standardError=log
        try process.run();let deadline=Date().addingTimeInterval(60)
        while process.isRunning && Date()<deadline { Thread.sleep(forTimeInterval:0.05) }
        let timedOut=process.isRunning
        if timedOut { process.terminate();let stop=Date().addingTimeInterval(2);while process.isRunning && Date()<stop{Thread.sleep(forTimeInterval:0.05)};if process.isRunning{kill(process.processIdentifier,SIGKILL)} }
        process.waitUntilExit()
        let text=try String(contentsOfFile:plan.log,encoding:.utf8)
        let complete = !timedOut && process.terminationStatus==0 && text.contains("frame limit reached")
        struct Result: Encodable {let complete:Bool;let timedOut:Bool;let exitCode:Int32;let log:String}
        try printJSON(Result(complete:complete,timedOut:timedOut,exitCode:process.terminationStatus,log:plan.log));exit(complete ? 0:1)
    } catch { fputs((error.localizedDescription+"\n"),stderr);exit(1) }
}

final class LauncherDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    let title=NSTextField(labelWithString:"Naruto Native Launcher")
    let subtitle=NSTextField(labelWithString:"Ultimate Ninja 5 · macOS Apple Silicon")
    let fileLabel=NSTextField(wrappingLabelWithString:"Selecione sua ISO para começar.")
    let status=NSTextField(wrappingLabelWithString:"A ISO permanece no seu computador. Nenhum arquivo é enviado pela internet.")
    let choose=NSButton(title:"Selecionar ISO…",target:nil,action:nil)
    let play=NSButton(title:"Jogar",target:nil,action:nil)
    let saves=NSButton(title:"Abrir pasta de saves",target:nil,action:nil)
    let scale=NSPopUpButton(frame:.zero,pullsDown:false)
    let cadenceNote=NSTextField(wrappingLabelWithString:"PAL: ritmo original da ISO europeia, aproximadamente 25 FPS na luta.")
    let mute=NSButton(checkboxWithTitle:"Silenciar o jogo",target:nil,action:nil)
    let progress=NSProgressIndicator()
    var selected:GameInspection?
    var profile:EngineProfile?
    var child:Process?
    var logHandle:FileHandle?
    var lockFD:Int32 = -1
    var busy=false
    func applicationDidFinishLaunching(_ notification:Notification) {
        let menu=NSMenu();let item=NSMenuItem();menu.addItem(item);let appMenu=NSMenu();item.submenu=appMenu
        appMenu.addItem(withTitle:"Encerrar inicializador",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q");NSApp.mainMenu=menu
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:660,height:560),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        window.title="Naruto Native Launcher";window.delegate=self;window.isReleasedWhenClosed=false
        let stack=NSStackView();stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=18;stack.edgeInsets=NSEdgeInsets(top:32,left:32,bottom:28,right:32)
        title.font = .systemFont(ofSize:29,weight:.bold);title.textColor = .labelColor
        subtitle.font = .systemFont(ofSize:14);subtitle.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize:13);status.textColor = .secondaryLabelColor
        fileLabel.font = .systemFont(ofSize:14,weight:.medium);fileLabel.maximumNumberOfLines=3
        let description=NSTextField(wrappingLabelWithString:"Use sua cópia europeia do jogo (SLES-55605). A edição será conferida antes de iniciar.")
        description.font = .systemFont(ofSize:14)
        choose.target=self;choose.action=#selector(pickISO);choose.bezelStyle = .rounded
        play.target=self;play.action=#selector(startGame);play.bezelStyle = .rounded;play.keyEquivalent="\r";play.isEnabled=false;play.contentTintColor = .systemOrange
        saves.target=self;saves.action=#selector(openSaves);saves.bezelStyle = .rounded
        scale.addItems(withTitles:["1× — original","2× — maior resolução"])
        mute.state = .on
        cadenceNote.font = .systemFont(ofSize:12);cadenceNote.textColor = .secondaryLabelColor
        let controls=NSTextField(wrappingLabelWithString:"Teclado: Z = X do PS2 · X = círculo · Enter = START · setas = mover")
        controls.font = .systemFont(ofSize:12);controls.textColor = .secondaryLabelColor
        let buttons=NSStackView(views:[choose,play,saves]);buttons.orientation = .horizontal;buttons.spacing=12
        progress.style = .bar;progress.isIndeterminate=true;progress.isDisplayedWhenStopped=false
        for view in [title,subtitle,description,fileLabel,buttons,scale,cadenceNote,mute,progress,status,controls] {stack.addArrangedSubview(view)}
        window.contentView=stack
        for view in [description,fileLabel,status,controls,progress,cadenceNote] {view.widthAnchor.constraint(equalToConstant:596).isActive=true}
        window.center();window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        if let path=UserDefaults.standard.string(forKey:"selectedISO"),FileManager.default.fileExists(atPath:path) {validate(URL(fileURLWithPath:path))}
    }
    func setBusy(_ value:Bool) {
        busy=value;choose.isEnabled = !value && child == nil;scale.isEnabled = !value && child == nil;mute.isEnabled = !value && child == nil
        play.isEnabled = !value && child == nil && profile != nil
        if value {progress.startAnimation(nil)}else{progress.stopAnimation(nil)}
    }
    @objc func pickISO() {
        let panel=NSOpenPanel();panel.allowedContentTypes=[UTType(filenameExtension:"iso") ?? .data];panel.canChooseDirectories=false;panel.allowsMultipleSelection=false
        panel.message="Selecione a ISO europeia do seu Ultimate Ninja 5."
        panel.beginSheetModal(for:window){result in if result == .OK,let url=panel.url{self.validate(url)}}
    }
    func validate(_ url:URL) {
        selected=nil;profile=nil;setBusy(true);fileLabel.stringValue=url.lastPathComponent;fileLabel.toolTip=url.path;status.stringValue="Conferindo a estrutura e a integridade da ISO…"
        DispatchQueue.global(qos:.userInitiated).async {
            do {
                let game=try inspectISO(url);let catalog=try readCatalog(resourceRoot)
                let profile=try? supportedGame(game,catalog)
                DispatchQueue.main.async {
                    self.selected=game;self.profile=profile
                    UserDefaults.standard.set(url.path,forKey:"selectedISO")
                    if profile != nil {
                        self.status.stringValue="ISO validada. Pronto para jogar."
                    }else if game.serial == "SLES_556.05" {
                        self.status.stringValue="Edição europeia identificada. Esta ISO ainda precisa de validação do motor nativo; a execução permanece indisponível nesta build."
                    }else{self.status.stringValue="Jogo ou região incompatível: \(game.serial). Selecione Ultimate Ninja 5 europeu (SLES-55605)."}
                    self.setBusy(false)
                }
            }catch{DispatchQueue.main.async{self.status.stringValue=error.localizedDescription;self.setBusy(false)}}
        }
    }
    @objc func startGame() {
        guard let selected=selected,let profile=profile,child==nil,!busy else{return}
        setBusy(true);status.stringValue="Preparando o jogo…";let selectedScale=scale.indexOfSelectedItem+1;let muted=mute.state == .on
        DispatchQueue.global(qos:.userInitiated).async {
            do {
                let game=try inspectISO(URL(fileURLWithPath:selected.path))
                try require(game.isoSHA256==selected.isoSHA256,"A ISO foi alterada. Selecione o arquivo novamente.")
                let plan=try makePlan(game,profile,resourceRoot,supportRoot().appendingPathComponent("Games/"+profile.id),scale:selectedScale,muted:muted)
                DispatchQueue.main.async{self.launch(plan)}
            }catch{DispatchQueue.main.async{self.status.stringValue=error.localizedDescription;self.setBusy(false)}}
        }
    }
    func launch(_ plan:LaunchPlan) {
        do {
            lockFD=open(supportRoot().appendingPathComponent("game.lock").path,O_CREAT|O_RDWR,0o600)
            try require(lockFD>=0 && flock(lockFD,LOCK_EX|LOCK_NB)==0,"Já existe um jogo aberto neste inicializador.")
            let process=Process();process.executableURL=URL(fileURLWithPath:plan.executable);process.arguments=plan.arguments;process.environment=plan.environment;process.currentDirectoryURL=URL(fileURLWithPath:plan.workingDirectory)
            let log=try openSessionLog(plan.log);logHandle=log;process.standardOutput=log;process.standardError=log
            process.terminationHandler={process in DispatchQueue.main.async {
                try? self.logHandle?.close();self.logHandle=nil;self.child=nil;if self.lockFD>=0{close(self.lockFD);self.lockFD = -1}
                let text=(try?String(contentsOfFile:plan.log,encoding:.utf8)) ?? ""
                let normal=process.terminationStatus==0 && text.contains("window closed")
                self.status.stringValue=normal ? "Jogo encerrado. Seus saves foram mantidos." : "O jogo encerrou inesperadamente. Consulte o log na pasta de saves."
                self.setBusy(false)
            }}
            try process.run();child=process;setBusy(false);status.stringValue="Jogo em execução. Feche a janela do jogo para retornar."
        }catch{try?logHandle?.close();logHandle=nil;if lockFD>=0{close(lockFD);lockFD = -1};status.stringValue=error.localizedDescription;setBusy(false)}
    }
    @objc func openSaves() {
        let directory=profile.map{supportRoot().appendingPathComponent("Games/"+$0.id)} ?? supportRoot()
        do{try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);NSWorkspace.shared.open(directory)}catch{status.stringValue=error.localizedDescription}
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {true}
    func windowShouldClose(_ sender:NSWindow)->Bool {
        if child != nil {status.stringValue="Feche primeiro a janela do jogo para encerrar o inicializador.";return false};return !busy
    }
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        if child != nil || busy {status.stringValue="Aguarde a operação atual e feche o jogo antes de encerrar.";window.makeKeyAndOrderFront(nil);return .terminateCancel};return .terminateNow
    }
}
if !cli() {
    let app=NSApplication.shared;let delegate=LauncherDelegate();app.delegate=delegate;app.setActivationPolicy(.regular);app.run()
}
