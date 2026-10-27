import Foundation

enum MacNowPlaying {
    private static let perl = URL(filePath: "/usr/bin/perl")
    private static let loader = #"use DynaLoader; my ($lib, $fn, $arg) = @ARGV; $ENV{NP_ARG} = $arg // ""; my $h = DynaLoader::dl_load_file($lib, 0) or exit 2; my $s = DynaLoader::dl_find_symbol($h, $fn) or exit 3; DynaLoader::dl_install_xsub("main::run", $s); run();"#
    private static let commands = ["toggle": 2, "next": 4, "previous": 5]
    private static var artwork: (id: String, base64: String)?

    private static var helper: URL? {
        Bundle.main.privateFrameworksURL?.appending(path: "libNowPlaying.dylib")
    }

    static func info() async -> JSON {
        guard var payload = await call("np_info") else { return [:] }
        if let base64 = payload.removeValue(forKey: "artwork") as? String, let id = payload["artworkId"] as? String {
            artwork = (id, base64)
        }
        return payload
    }

    static func artworkPayload(id: String?) -> JSON? {
        guard let artwork, id == artwork.id else { return nil }
        return ["id": artwork.id, "data": artwork.base64]
    }

    static func perform(_ request: JSON) async -> Bool {
        if let name = request["command"] as? String, let command = commands[name] {
            return await call("np_command", argument: String(command))?["ok"] as? Bool == true
        }
        if let seconds = request["seek"] as? Double, seconds.isFinite, seconds >= 0 {
            return await call("np_seek", argument: String(seconds))?["ok"] as? Bool == true
        }
        return false
    }

    private static func call(_ function: String, argument: String = "") async -> JSON? {
        guard let helper,
              let data = await ProcessRunner.output(of: perl, arguments: ["-e", loader, helper.path, function, argument], timeout: .seconds(5)) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? JSON
    }
}
