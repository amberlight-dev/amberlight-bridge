import Foundation

struct MascotSprite {
    static let columns = 14
    static let eye: Character = "e"

    let body: [String]
    let rest: [String]
    let steps: [[String]]
    let palette: [Character: UInt32]
    let lid: Character
    let petal: UInt32
    let swayRows: Int

    func rows(step: Int, swaying: Bool, moving: Bool) -> [String] {
        let crown = body.enumerated().map { index, row in
            swaying && index < swayRows ? "." + row.dropLast() : row
        }
        return crown + (moving ? steps[step % steps.count] : rest)
    }
}

extension Mascot {
    var sprite: MascotSprite {
        switch self {
        case .sapling: Self.saplingSprite
        case .cactus: Self.cactusSprite
        case .cloud: Self.cloudSprite
        case .robot: Self.robotSprite
        case .mushroom: Self.mushroomSprite
        }
    }

    private static let saplingSprite = MascotSprite(
        body: [
            "....GGGGGG....",
            "..GGGgggggdd..",
            ".GGggggggggdd.",
            ".Gggggggggggd.",
            "GGgggggggggggd",
            "Gggegggggegggd",
            "Gggegggggegggd",
            ".ggggggggggdd.",
            "..gdggggggdd..",
            "...dd.bb.dd...",
            "......bB......",
            ".....bbBB.....",
        ],
        rest: ["....bB..bB...."],
        steps: [["....bB..bB...."], ["...bB....bB..."]],
        palette: ["G": 0xA6E07C, "g": 0x5FBF65, "d": 0x2E8B57, "b": 0xA87B4F, "B": 0x6F4E33, "e": 0x0E1512],
        lid: "g",
        petal: 0xFFB7CF,
        swayRows: 4
    )

    private static let cactusSprite = MascotSprite(
        body: [
            "......pp......",
            ".....pPPp.....",
            "....GGGGGG....",
            "....GgGGgG....",
            ".GG.GgGGgG....",
            ".GG.GeGGeG.GG.",
            ".GG.GeGGeG.GG.",
            ".GGGGgGGgG.GG.",
            "..GGGgGGgGGGG.",
            "....GgGGgGGG..",
            "....GgGGgG....",
            "...TTTTTTTT...",
        ],
        rest: ["....tTTTTt...."],
        steps: [["....tTTTTt...."]],
        palette: ["G": 0x6CC77A, "g": 0x3E9B5A, "p": 0xFF8FB8, "P": 0xFFD1E2, "T": 0x6C7FA6, "t": 0x4A5A7D, "e": 0x0E1512],
        lid: "G",
        petal: 0xFF8FB8,
        swayRows: 2
    )

    private static let cloudSprite = MascotSprite(
        body: [
            ".....WWW......",
            "..WW.WWWWW....",
            ".WWWWWWWWWWW..",
            "WWWWWWWWWWWWW.",
            "WWWeWWWWWeWWWW",
            "WWWeWWWWWeWWWW",
            "WWWWWWWWWWWWWW",
            ".LLLLLLLLLLLL.",
        ],
        rest: ["..............", ".............."],
        steps: [["..r....r...r..", "....r....r...."], ["....r....r....", "..r....r...r.."]],
        palette: ["W": 0xF2F6FF, "L": 0xB9C7E8, "r": 0x7FC8FF, "e": 0x1B2233],
        lid: "W",
        petal: 0x7FC8FF,
        swayRows: 0
    )

    private static let robotSprite = MascotSprite(
        body: [
            "......aa......",
            "......ss......",
            "..SSSSSSSSSS..",
            "..SkkkkkkkkS..",
            "..SkekkkkekS..",
            "..SkekkkkekS..",
            "..SkkkkkkkkS..",
            "..SSSSSSSSSS..",
            "...DDDDDDDD...",
            ".ssDDDaaDDDss.",
            ".s.DDDDDDDD.s.",
            "...DDDDDDDD...",
        ],
        rest: ["....ss..ss...."],
        steps: [["....ss..ss...."], ["...ss....ss..."]],
        palette: ["S": 0xC9D3E3, "s": 0x8E9AB3, "k": 0x1A2333, "D": 0xA9B6CC, "a": 0x6FE3D6, "e": 0x6FE3D6],
        lid: "k",
        petal: 0x6FE3D6,
        swayRows: 0
    )

    private static let mushroomSprite = MascotSprite(
        body: [
            "....VVVVVV....",
            "..VVwVVVVwVV..",
            ".VVVVVVVVVVVV.",
            "VVwVVVVVVVVwVV",
            "VVVVVwwVVVVVVV",
            ".vvvvvvvvvvvv.",
            "...FFFFFFFF...",
            "...FeFFFFeF...",
            "...FeFFFFeF...",
            "...FFFFFFFF...",
            "....FFFFFF....",
        ],
        rest: ["....fF..fF...."],
        steps: [["....fF..fF...."], ["...fF....fF..."]],
        palette: ["V": 0x9B6BF0, "w": 0xEDE6FF, "v": 0x5E3FB0, "F": 0xF3E9D8, "f": 0xCDBFA6, "e": 0x1A1424],
        lid: "F",
        petal: 0xC7B0FF,
        swayRows: 0
    )
}
