import Vapor
import JWT

struct UserPayload: JWTPayload, Authenticatable {
    var sub: SubjectClaim
    var exp: ExpirationClaim
    var userId: UUID
    var email: String
    var role: String
    var nom: String

    func verify(using signer: JWTSigner) throws {
        try self.exp.verifyNotExpired()
    }
}

struct JWTMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        print("JWTMiddleware")
        guard let token = request.headers.bearerAuthorization?.token else {
            throw Abort(.unauthorized, reason: "Token manquant")
        }
        print("Token présent")

        let payload = try request.jwt.verify(token, as: UserPayload.self)
        print("Payload òk")
        print(payload)

        request.auth.login(payload)
        print("logged in")
        return try await next.respond(to: request)
    }
}

struct AdminMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let payload = try request.auth.require(UserPayload.self)
        guard payload.role == "admin" else {
            throw Abort(.forbidden, reason: "Accès administrateur requis")
        }
        return try await next.respond(to: request)
    }
}

// Zitadel JWT Payload
struct ZitadelPayload: JWTPayload, Authenticatable {
    var sub: SubjectClaim  // Zitadel User ID
    var exp: ExpirationClaim
    var iat: IssuedAtClaim?
    var iss: IssuerClaim?
    var aud: AudienceClaim?
    
    func verify(using signer: JWTSigner) throws {
        try self.exp.verifyNotExpired()
    }
}
