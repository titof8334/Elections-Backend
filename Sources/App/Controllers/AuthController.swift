import Vapor
import Fluent
import JWT

struct AuthController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.post("login", use: login)
        routes.post("register", use: register) // Admin only via admin controller
        routes.get("me", use: me)
    }

    func login(req: Request) async throws -> LoginResponse {
        let loginReq = try req.content.decode(LoginRequest.self)

        guard let user = try await User.query(on: req.db)
            .filter(\.$email == loginReq.email)
            .with(\.$bureaux)
            .first() else {
            throw Abort(.unauthorized, reason: "Email ou mot de passe incorrect")
        }

        guard try Bcrypt.verify(loginReq.password, created: user.passwordHash) else {
            throw Abort(.unauthorized, reason: "Email ou mot de passe incorrect")
        }

        let payload = UserPayload(
            sub: .init(value: user.id!.uuidString),
            exp: .init(value: Date().addingTimeInterval(60 * 60 * 12)), // 12h
            userId: user.id!,
            email: user.email,
            role: user.role,
            nom: user.nom
        )

        let token = try req.jwt.sign(payload)
        let bureauIds = user.bureaux.compactMap { $0.id }

        return LoginResponse(
            token: token,
            user: UserDTO(
                id: user.id!,
                nom: user.nom,
                email: user.email,
                role: user.role,
                bureaux: bureauIds,
                prenom: user.prenom,
                dispBureauId: user.$dispBureau.id,
                dispAssesseur: user.dispAssesseur,
                dispDelegue: user.dispDelegue
            )
        )
    }

    func register(req: Request) async throws -> UserDTO {
        let createReq = try req.content.decode(CreateUserRequest.self)

        let existingUser = try await User.query(on: req.db)
            .filter(\.$email == createReq.email)
            .first()

        if existingUser != nil {
            throw Abort(.conflict, reason: "Cet email est déjà utilisé")
        }

        let hash = try Bcrypt.hash(createReq.password)
        let user = User(
            nom: createReq.nom,
            email: createReq.email,
            passwordHash: hash,
            role: createReq.role ?? "scrutateur",
            zitadelSub: nil,
            prenom: createReq.prenom,
            dispAssesseur: createReq.dispAssesseur ?? false,
            dispDelegue: createReq.dispDelegue ?? false
        )
        
        // Set dispBureau if provided
        if let dispBureauId = createReq.dispBureauId {
            user.$dispBureau.id = dispBureauId
        }
        
        try await user.save(on: req.db)

        // Associate bureaux if provided
        if let bureauIds = createReq.bureauIds {
            for bureauId in bureauIds {
                if let bureau = try await Bureau.find(bureauId, on: req.db) {
                    try await user.$bureaux.attach(bureau, on: req.db)
                }
            }
        }

        return UserDTO(
            id: user.id!,
            nom: user.nom,
            email: user.email,
            role: user.role,
            bureaux: createReq.bureauIds ?? [],
            prenom: user.prenom,
            dispBureauId: user.$dispBureau.id,
            dispAssesseur: user.dispAssesseur,
            dispDelegue: user.dispDelegue
        )
    }
    
    func me(req: Request) async throws -> MeResponse {
        // Extract Bearer token
        guard let bearerToken = req.headers.bearerAuthorization?.token else {
            throw Abort(.unauthorized, reason: "Token manquant")
        }

        // Validate Zitadel token via JWKS or introspection
        let zitadelPayload = try await req.zitadel.validateToken(bearerToken)
        req.logger.info("Token validated. Sub: \(zitadelPayload.sub.value)")

        // Find or create user by Zitadel sub
        let user: User
        
        // Step 1: Try to find user by zitadelSub
        if let existingUser = try await User.query(on: req.db)
            .filter(\.$zitadelSub == zitadelPayload.sub.value)
            .with(\.$bureaux)
            .first() {
            user = existingUser
            req.logger.info("User found by zitadelSub: \(user.email)")
        } else {
            // Step 2: User not found by zitadelSub, try to get email from token
            // Note: Email might be in a userinfo endpoint call, not directly in the token
            // For now, we'll need to make an additional call to Zitadel's userinfo endpoint
            
            let userInfo = try await req.zitadel.fetchUserInfo(accessToken: bearerToken)
            req.logger.info("Fetched user info. Email: \(userInfo.email ?? "none")")
            
            // Step 3: Try to find existing user by email (to link accounts)
            if let email = userInfo.email,
               let existingUserByEmail = try await User.query(on: req.db)
                .filter(\.$email == email)
                .with(\.$bureaux)
                .first() {
                // Link existing user to Zitadel
                req.logger.info("Found existing user by email, linking to Zitadel sub")
                existingUserByEmail.zitadelSub = zitadelPayload.sub.value
                
                // Update name if available in userinfo
                if let givenName = userInfo.given_name {
                    existingUserByEmail.prenom = givenName
                }
                if let familyName = userInfo.family_name {
                    existingUserByEmail.nom = familyName
                }
                
                try await existingUserByEmail.save(on: req.db)
                user = existingUserByEmail
                req.logger.info("User account linked to Zitadel")
            } else {
                // Step 4: Create new user
                req.logger.info("Creating new user with sub: \(zitadelPayload.sub.value)")
                
                let newUser = User(
                    nom: userInfo.family_name ?? "Utilisateur",
                    email: userInfo.email ?? "user-\(zitadelPayload.sub.value)@zitadel.local",
                    passwordHash: "",  // No password for Zitadel users
                    role: "scrutateur",  // Default role
                    zitadelSub: zitadelPayload.sub.value,
                    prenom: userInfo.given_name
                )
                
                try await newUser.save(on: req.db)
                
                // Reload with relations
                guard let savedUser = try await User.query(on: req.db)
                    .filter(\.$zitadelSub == zitadelPayload.sub.value)
                    .with(\.$bureaux)
                    .first() else {
                    throw Abort(.internalServerError, reason: "Failed to create user")
                }
                
                user = savedUser
                req.logger.info("New user created with id: \(user.id?.uuidString ?? "unknown")")
            }
        }
        
        let bureauIds = user.bureaux.compactMap { $0.id }
        
        return MeResponse(
            role: user.role,
            bureaux: bureauIds,
            nom: user.nom,
            prenom: user.prenom
        )
    }
}
