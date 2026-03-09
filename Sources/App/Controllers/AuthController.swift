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
            .first() else {
            throw Abort(.unauthorized, reason: "Email ou mot de passe incorrect")
        }

        guard try Bcrypt.verify(loginReq.password, created: user.passwordHash) else {
            throw Abort(.unauthorized, reason: "Email ou mot de passe incorrect")
        }

        let userBureaux = try await UserBureau.query(on: req.db)
            .filter(\.$user.$id == user.id!)
            .all()
        let userElections = try await UserElection.query(on: req.db)
            .filter(\.$user.$id == user.id!)
            .all()
        let payload = UserPayload(
            sub: .init(value: user.id!.uuidString),
            exp: .init(value: Date().addingTimeInterval(60 * 60 * 12)), // 12h
            userId: user.id!,
            email: user.email,
            nom: user.nom,
            isAdmin: user.isAdmin
        )

        let token = try req.jwt.sign(payload)
        let elections = userElections.compactMap {
            MeUserElection(electionId: $0.$election.id, isOwner: $0.isOwner, role: $0.role, dispBureauId: $0.$dispBureau.id, dispDelegue: $0.dispDelegue, dispAssesseur: $0.dispAssesseur, periode: $0.periode)
        }
        let bureaux = userBureaux.compactMap {
            MeUserBureau(electionId: $0.$election.id, bureauId: $0.$bureau.id, periode: $0.periode)
        }

        return LoginResponse(
            token: token,
            user: MeResponse(
                id: user.id!,
                nom: user.nom,
                prenom: user.prenom,
                email: user.email,
                isAdmin: user.isAdmin,
                bureaux: bureaux,
                elections: elections
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

        let hash = try Bcrypt.hash(createReq.password ?? "")
        let user = User(
            nom: createReq.nom,
            email: createReq.email,
            passwordHash: hash,
            zitadelSub: nil,
            prenom: createReq.prenom,
        )
        
        try await user.save(on: req.db)

        return UserDTO(
            id: user.id!,
            nom: user.nom,
            prenom: user.prenom,
            email: user.email,
            isAdmin: user.isAdmin
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
                    zitadelSub: zitadelPayload.sub.value,
                    prenom: userInfo.given_name
                )
                
                try await newUser.save(on: req.db)
                
                // Reload with relations
                guard let savedUser = try await User.query(on: req.db)
                    .filter(\.$zitadelSub == zitadelPayload.sub.value)
                    .first() else {
                    throw Abort(.internalServerError, reason: "Failed to create user")
                }
                
                user = savedUser
                req.logger.info("New user created with id: \(user.id?.uuidString ?? "unknown")")
            }
        }
        
        // Load UserBureau pivots
        let userBureaux = try await UserBureau.query(on: req.db)
            .filter(\.$user.$id == user.requireID())
            .with(\.$bureau)
            .all()
        
        let bureaux = userBureaux.compactMap { ub -> MeUserBureau? in
            guard let bureauId = ub.bureau.id else { return nil }
            return MeUserBureau(electionId: ub.$election.id, bureauId: bureauId, periode: ub.periode)
        }
        
        // Load UserElection pivots
        let userElections = try await UserElection.query(on: req.db)
            .filter(\.$user.$id == user.requireID())
            .with(\.$election)
            .all()
        
        let elections = userElections.compactMap { ue -> MeUserElection? in
            guard let electionId = ue.election.id else { return nil }
            return MeUserElection(
                electionId: electionId,
                isOwner: ue.isOwner,
                role: ue.role,
                dispBureauId: ue.$dispBureau.id,
                dispDelegue: ue.dispDelegue,
                dispAssesseur: ue.dispAssesseur,
                periode: ue.periode
            )
        }
        
        return MeResponse(
            id: user.id ?? UUID(),
            nom: user.nom,
            prenom: user.prenom,
            email: user.email,
            isAdmin: user.isAdmin,
            bureaux: bureaux,
            elections: elections,
        )
    }
}
