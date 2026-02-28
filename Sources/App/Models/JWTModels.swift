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
        guard let token = request.headers.bearerAuthorization?.token else {
            throw Abort(.unauthorized, reason: "Token manquant")
        }
        let payload = try request.jwt.verify(token, as: UserPayload.self)
        request.auth.login(payload)
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
