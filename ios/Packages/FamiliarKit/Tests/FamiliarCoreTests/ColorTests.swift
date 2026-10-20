import Testing
@testable import FamiliarCore

struct RGBColorTests {
    @Test func parsesHexWithAndWithoutHash() throws {
        let withHash = try #require(RGBColor(hex: "#FFA43A"))
        let withoutHash = try #require(RGBColor(hex: "ffa43a"))
        #expect(withHash == withoutHash)
        #expect(withHash.red == 1)
        #expect(abs(withHash.green - 164.0 / 255) < 1e-9)
        #expect(withHash.hexString == "#FFA43A")
    }

    @Test(arguments: ["", "#FFF", "#GGGGGG", "#1234567", "rot"])
    func rejectsInvalidHex(_ input: String) {
        #expect(RGBColor(hex: input) == nil)
    }
}

struct OKLabTests {
    @Test func whiteAndBlackHaveExpectedLightness() {
        let white = OKLab(RGBColor(hex: 0xFFFFFF))
        let black = OKLab(RGBColor(hex: 0x000000))
        #expect(abs(white.lightness - 1) < 1e-4)
        #expect(abs(white.a) < 1e-4 && abs(white.b) < 1e-4)
        #expect(abs(black.lightness) < 1e-9)
    }

    @Test func roundTripPreservesColor() {
        for hex: UInt32 in [0xFF7F66, 0xF7C548, 0x8FD19E, 0x5EC2F2, 0xB39DFF, 0x14100D] {
            let original = RGBColor(hex: hex)
            let roundTrip = OKLab(original).rgb
            #expect(abs(roundTrip.red - original.red) < 1e-6)
            #expect(abs(roundTrip.green - original.green) < 1e-6)
            #expect(abs(roundTrip.blue - original.blue) < 1e-6)
        }
    }
}

struct FamilyColorResolverTests {
    private let coral = RGBColor(hex: 0xFF7F66)
    private let sky = RGBColor(hex: 0x5EC2F2)

    @Test func keepsDistinctColorsUnchanged() {
        let result = FamilyColorResolver.displayColors(for: [
            FamilyColorInput(familyID: "a", color: coral),
            FamilyColorInput(familyID: "b", color: sky),
        ])
        #expect(result["a"]?.hexString == coral.hexString)
        #expect(result["b"]?.hexString == sky.hexString)
    }

    @Test func separatesIdenticalColors() throws {
        let result = FamilyColorResolver.displayColors(for: [
            FamilyColorInput(familyID: "a", color: coral),
            FamilyColorInput(familyID: "b", color: coral),
        ])
        let first = try #require(result["a"])
        let second = try #require(result["b"])
        // Die erste Familie (nach ID) behält ihre Originalfarbe.
        #expect(first.hexString == coral.hexString)
        #expect(OKLab(first).distance(to: OKLab(second)) >= FamilyColorResolver.minimumDistance)
    }

    @Test func separatesThreeSimilarGreys() {
        let greys = [0x808080, 0x828282, 0x7E7E7E].enumerated().map {
            FamilyColorInput(familyID: "f\($0.offset)", color: RGBColor(hex: UInt32($0.element)))
        }
        let labs = FamilyColorResolver.displayColors(for: greys).values.map(OKLab.init)
        for (i, lhs) in labs.enumerated() {
            for rhs in labs[(i + 1)...] {
                #expect(lhs.distance(to: rhs) >= FamilyColorResolver.minimumDistance)
            }
        }
    }

    @Test func isIndependentOfInputOrder() {
        let inputs = [
            FamilyColorInput(familyID: "c", color: coral),
            FamilyColorInput(familyID: "a", color: coral),
            FamilyColorInput(familyID: "b", color: RGBColor(hex: 0xFF8066)),
        ]
        #expect(
            FamilyColorResolver.displayColors(for: inputs)
                == FamilyColorResolver.displayColors(for: inputs.reversed())
        )
    }
}
