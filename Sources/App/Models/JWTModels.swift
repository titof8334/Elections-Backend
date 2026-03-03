import Vapor
import Fluent
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

// Zitadel Authentication Middleware
struct ZitadelAuthMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard let token = request.headers.bearerAuthorization?.token else {
            throw Abort(.unauthorized, reason: "Token manquant")
        }
        
        // Validate token with Zitadel
        let zitadelPayload = try await request.zitadel.validateToken(token)
        
        // Find user in database
        guard let user = try await User.query(on: request.db)
            .filter(\.$zitadelSub == zitadelPayload.sub.value)
            .first() else {
            throw Abort(.unauthorized, reason: "Utilisateur non trouvé ou non autorisé")
        }
        
        // Create internal UserPayload for compatibility with existing code
        let userPayload = UserPayload(
            sub: .init(value: user.id!.uuidString),
            exp: zitadelPayload.exp,
            userId: user.id!,
            email: user.email,
            role: user.role,
            nom: user.nom
        )
        
        request.auth.login(userPayload)
        return try await next.respond(to: request)
    }
}

// Admin middleware for Zitadel users
struct ZitadelAdminMiddleware: AsyncMiddleware {
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
    var aud: [String]?
    var azp: String?
    var client_id: String?
    var jti: String?
    var nbf: Int?
    var scope: String?
    
    enum CodingKeys: String, CodingKey {
        case sub, exp, iat, iss, aud, azp, client_id, jti, nbf, scope
    }
    
    func verify(using signer: JWTSigner) throws {
        try self.exp.verifyNotExpired()
    }
}
