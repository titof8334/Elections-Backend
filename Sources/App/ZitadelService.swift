import Vapor
import JWT
import JWTKit

actor ZitadelServiceActor {
    let jwksURL = "https://auth.carnal.cloud/oauth/v2/keys"
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

    /// Validates a Zitadel JWT token and returns the payload
    func validateToken(_ token: String) async throws -> ZitadelPayload {
        do {
            app.logger.info("Fetching JWKS from Zitadel...")
            let jwks = try await fetchJWKS()
            app.logger.info("JWKS fetched successfully, \(jwks.keys.count) keys found")

            // Create signers from JWKS
            let signers = JWTSigners()
            for key in jwks.keys {
                try signers.use(jwk: key)
            }

            app.logger.info("Attempting to verify token...")
            // Verify and decode the token
            let payload = try signers.verify(token, as: ZitadelPayload.self)
            app.logger.info("Token verified successfully. Sub: \(payload.sub.value)")

            return payload
        } catch let error as JWTError {
            app.logger.error("JWT Error: \(error)")
            throw Abort(.unauthorized, reason: "Invalid JWT token: \(error.localizedDescription)")
        } catch {
            app.logger.error("Token validation error: \(error)")
            throw Abort(.unauthorized, reason: "Token validation failed: \(error.localizedDescription)")
        }
    }
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
