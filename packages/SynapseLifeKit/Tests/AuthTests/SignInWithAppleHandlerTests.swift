import Foundation
import Testing
@testable import Auth

private struct StubCredential: AppleCredentialLike {
    let user: String
    let identityToken: Data?
    let email: String?
    let fullName: PersonNameComponents?
}

@Suite("SignInWithAppleHandler")
struct SignInWithAppleHandlerTests {

    @Test
    func mapsAllFieldsWhenPresent() throws {
        let handler = SignInWithAppleHandler()
        var name = PersonNameComponents()
        name.givenName = "Antonio"
        name.familyName = "Mastropaolo"
        let stub = StubCredential(
            user: "001234.deadbeef",
            identityToken: Data([0x01, 0x02, 0x03]),
            email: "a@example.com",
            fullName: name
        )
        let result = try handler.handle(stub)
        #expect(result.userId == "001234.deadbeef")
        #expect(result.email == "a@example.com")
        #expect(result.fullName?.givenName == "Antonio")
        #expect(result.fullName?.familyName == "Mastropaolo")
        #expect(result.identityToken == Data([0x01, 0x02, 0x03]))
    }

    @Test
    func mapsRequiredFieldsWhenOptionalsAbsent() throws {
        // Apple only returns full name + email on first sign-in. Subsequent
        // sign-ins for the same user return identityToken + user only.
        let handler = SignInWithAppleHandler()
        let stub = StubCredential(
            user: "u",
            identityToken: Data([0xFF]),
            email: nil,
            fullName: nil
        )
        let result = try handler.handle(stub)
        #expect(result.userId == "u")
        #expect(result.email == nil)
        #expect(result.fullName == nil)
        #expect(result.identityToken == Data([0xFF]))
    }

    @Test
    func throwsWhenIdentityTokenMissing() {
        let handler = SignInWithAppleHandler()
        let stub = StubCredential(
            user: "u",
            identityToken: nil,
            email: nil,
            fullName: nil
        )
        #expect(throws: AppleSignInError.missingIdentityToken) {
            _ = try handler.handle(stub)
        }
    }
}
