import Vapor
import JWT
import JWTKit

actor ZitadelServiceActor {
    let jwksURL = "https://auth.carnal.cloud/oauth/v2/keys"
    let introspectionURL = "https://auth.carnal.cloud/oauth/v2/introspect"
    let app: Application
    private var jwksCache: JWKS?
    private var lastFetch: Date?
    private let cacheDuration: TimeInterval = 3600 // 1 hour

    init(app: Application) {
        self.app = app
    }

    /// Fetches and caches JWKS from Zitadel
    func fetchJWKS() async throws -> JWKS {
        // Return cached JWKS if still valid
        if let cached = jwksCache,
           let lastFetch = lastFetch,
           Date().timeIntervalSince(lastFetch) < cacheDuration {
            return cached
        }

        // Fetch fresh JWKS
        let response = try await app.client.get(URI(string: jwksURL))
        guard response.status == .ok else {
            throw Abort(.internalServerError, reason: "Failed to fetch JWKS from Zitadel")
        }

        let jwks = try response.content.decode(JWKS.self)
        self.jwksCache = jwks
        self.lastFetch = Date()

        return jwks
    }

    /// Validates a Zitadel token via introspection endpoint (for opaque tokens)
    func introspectToken(_ token: String) async throws -> IntrospectionResponse {
        app.logger.info("Token introspection via Zitadel...")

        // Get client credentials from environment
        guard let clientId = Environment.get("ZITADEL_CLIENT_ID"),
              let clientSecret = Environment.get("ZITADEL_CLIENT_SECRET") else {
            throw Abort(.internalServerError, reason: "Missing Zitadel client credentials")
        }

        app.logger.info("Using client_id: \(clientId)")

        var headers = HTTPHeaders()
        headers.basicAuthorization = .init(username: clientId, password: clientSecret)
        headers.contentType = .urlEncodedForm

        // Prepare form data
        struct IntrospectionRequest: Content {
            let token: String
        }

        let requestData = IntrospectionRequest(token: token)

        let response = try await app.client.post(URI(string: introspectionURL), headers: headers) { req in
            try req.content.encode(requestData, as: .urlEncodedForm)
        }

        guard response.status == .ok else {
            app.logger.error("Introspection failed with status: \(response.status)")
            if let body = response.body {
                let errorMessage = String(buffer: body)
                app.logger.error("Error response body: \(errorMessage)")
            }
            throw Abort(.unauthorized, reason: "Token introspection failed")
        }

        let introspection = try response.content.decode(IntrospectionResponse.self)

        guard introspection.active else {
            app.logger.warning("Token is not active")
            throw Abort(.unauthorized, reason: "Token is not active")
        }

        app.logger.info("Token introspection successful. Sub: \(introspection.sub)")
        return introspection
    }

    /// Validates a Zitadel JWT token and returns the payload
    func validateToken(_ token: String) async throws -> ZitadelPayload {
        // Check if token looks like a JWT (has 2 dots)
        let parts = token.split(separator: ".")

        if parts.count == 3 {
            // Try JWT validation
            do {
                app.logger.info("Token appears to be JWT format, attempting JWKS validation...")
                let jwks = try await fetchJWKS()
                app.logger.info("JWKS fetched successfully, \(jwks.keys.count) keys found")

                let signers = JWTSigners()
                for key in jwks.keys {
                    try signers.use(jwk: key)
                }

                app.logger.info("Attempting to verify JWT token...")
                let payload = try signers.verify(token, as: ZitadelPayload.self)
                app.logger.info("JWT verified successfully. Sub: \(payload.sub.value)")

                return payload
            } catch let error as JWTError {
                app.logger.error("JWT validation failed: \(error)")
                throw Abort(.unauthorized, reason: "Invalid JWT token: \(error.localizedDescription)")
            }
        } else {
            // Token is opaque, use introspection
            app.logger.info("Token appears to be opaque, using introspection...")
            let introspection = try await introspectToken(token)

            // Convert introspection response to ZitadelPayload
            return ZitadelPayload(
                sub: .init(value: introspection.sub),
                exp: .init(value: Date(timeIntervalSince1970: TimeInterval(introspection.exp))),
                iat: introspection.iat.map { .init(value: Date(timeIntervalSince1970: TimeInterval($0))) },
                iss: introspection.iss.map { .init(value: $0) },
                aud: introspection.aud,
                azp: introspection.client_id,
                client_id: introspection.client_id,
                jti: nil,
                nbf: introspection.nbf,
                scope: introspection.scope
            )
        }
    }
}

// Introspection response from Zitadel
struct IntrospectionResponse: Content {
    let active: Bool
    let sub: String
    let exp: Int
    let iat: Int?
    let iss: String?
    let aud: [String]?
    let client_id: String?
    let scope: String?
    let nbf: Int?
    let token_type: String?
    let username: String?
}

// Storage key for ZitadelService
struct ZitadelServiceKey: StorageKey {
    typealias Value = ZitadelServiceActor
}

extension Application {
    var zitadel: ZitadelServiceActor {
        get {
            if let existing = self.storage[ZitadelServiceKey.self] {
                return existing
            }
            let new = ZitadelServiceActor(app: self)
            self.storage[ZitadelServiceKey.self] = new
            return new
        }
        set {
            self.storage[ZitadelServiceKey.self] = newValue
        }
    }
}

extension Request {
    var zitadel: ZitadelServiceActor {
        return self.application.zitadel
    }
}
