import Vapor
import Fluent

struct AuthUserController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.put("me", use: updateMe)
        routes.put("me","userElection", ":userElectionId", use: updateMyPrefs)
        routes.post("me","elections", ":electionId", use: joinElection)
        routes.delete("me","elections", ":electionId", use: leaveElection)
        routes.get("me","elections", use: joinedElections)
        routes.get("me","profile", use: myProfile)
    }
    
    func updateMe(req: Request) async throws -> UserDTO {
        let payload = try req.auth.require(UserPayload.self)
        
        guard let user = try await User.find(payload.userId, on: req.db) else { throw Abort(.notFound) }
        let updateReq = try req.content.decode(UserDTO.self)
        user.nom = updateReq.nom ?? user.nom
        user.prenom=updateReq.prenom ?? user.prenom
        user.email=updateReq.email ?? user.email
        user.isAdmin=updateReq.isAdmin ?? user.isAdmin
        try await user.save(on: req.db)
        return UserDTO(
            id: user.id!,
            nom: user.nom,
            prenom: user.prenom,
            email: user.email,
            isAdmin: user.isAdmin
        )
    }
    func updateMyPrefs(req: Request) async throws -> UserElectionDTO {
        guard let userElectionId = req.parameters.get("userElectionId", as: UUID.self) else {
            print("pas de userElectionId")
            throw Abort(.badRequest)
        }
        guard let prefs = try await UserElection.find(userElectionId,on: req.db)
            else {
            print("pas de UserElection")
                throw Abort(.forbidden, reason: "Rattachez-vous d'abord à cette élection.")
        }
        print("Décodage")
        let updateReq = try req.content.decode(UserElectionDTO.self)
        print("Décodage OK")
        prefs.$dispBureau.id = updateReq.dispBureauId
        prefs.dispAssesseur = updateReq.dispAssesseur ?? prefs.dispAssesseur
        prefs.dispDelegue = updateReq.dispDelegue ?? prefs.dispDelegue
        prefs.periode = updateReq.periode ?? prefs.periode
        print("tentative sauvegarde")
        try await prefs.save(on: req.db)
        print("Sauvegarde OK")
        print(UserElectionDTO(
            id: prefs.id!,
            dispBureauId: prefs.$dispBureau.id,
            dispAssesseur: prefs.dispAssesseur,
            dispDelegue: prefs.dispDelegue,
            periode: prefs.periode
        ))
        return UserElectionDTO(
            id: prefs.id!,
            dispBureauId: prefs.$dispBureau.id,
            dispAssesseur: prefs.dispAssesseur,
            dispDelegue: prefs.dispDelegue,
            periode: prefs.periode
        )
    }
    
    func joinElection(req: Request) async throws -> UserElectionDTO {
        let payload = try req.auth.require(UserPayload.self)
    
        guard let electionId = req.parameters.get("electionId", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        if (try await UserElection.query(on: req.db)
            .filter(\.$user.$id == payload.userId)
            .filter(\.$election.$id == electionId)
            .first()) != nil {
            throw Abort(.badRequest, reason: "Vous êtes déjà rattaché à cette élection.")
        }

//        let createReq = try req.content.decode(UserElectionDTO.self)
        let prefs = UserElection(
            userID: payload.userId,
            electionID: electionId,
            dispBureauId: nil,
            dispAssesseur: false,
            dispDelegue: false,
            periode: "J"
        )
        try await prefs.save(on: req.db)
        return UserElectionDTO(
            id: prefs.id!,
            dispBureauId: prefs.$dispBureau.id,
            dispAssesseur: prefs.dispAssesseur,
            dispDelegue: prefs.dispDelegue,
            periode: prefs.periode
        )
    }
    func leaveElection(req: Request) async throws -> HTTPStatus {
        let payload = try req.auth.require(UserPayload.self)
    
        guard let electionId = req.parameters.get("electionId", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        try await UserElection.query(on: req.db)
            .filter(\.$user.$id == payload.userId)
            .filter(\.$election.$id == electionId)
            .delete()
        return .noContent
    }

    func joinedElections(req: Request) async throws -> [ElectionDTO] {
        let payload = try req.auth.require(UserPayload.self)
        let ues = try await UserElection.query(on: req.db)
            .filter(\.$user.$id == payload.userId)
            .with(\.$election)
            .all()
        return ues.map { e in
            ElectionDTO(id: e.election.id, nom: e.election.nom, isOwner: e.isOwner, isDelegue: e.role == "delegue", isSubscriber: true)
        }
    }
    
    func myProfile(req: Request) async throws -> MeProfile {
        let payload = try req.auth.require(UserPayload.self)
        guard let user = try await User.find(payload.userId, on: req.db) else { throw Abort(.notFound) }
        let ues = try await UserElection.query(on: req.db)
            .filter(\.$user.$id == payload.userId)
            .with(\.$election)
            .all()
        let ubs = try await UserBureau.query(on: req.db)
            .filter(\.$user.$id == payload.userId)
            .all()
        let electionsId = ues.compactMap { $0.$election.id }
        let bureaux = try await Bureau.query(on: req.db)
            .filter(\.$election.$id ~~ electionsId)
            .all()
        let mpes = ues.map { ue in
            let mpebs = ubs
                .filter { $0.$election.id == ue.$election.id }
                .map { MeProfileElectionBureau(id: $0.id, bureauId: $0.$bureau.id, periode: $0.periode) }
            let mpbs = bureaux
                .filter { $0.$election.id == ue.$election.id }
                .map { MeProfileBureau(id: $0.id, numero: $0.numero, nom: $0.nom)}
            return MeProfileElection(id: ue.id, electionId: ue.$election.id, nom: ue.election.nom, isOwner: ue.isOwner, role: ue.role, dispBureauId: ue.$dispBureau.id, dispDelegue: ue.dispDelegue, dispAssesseur: ue.dispAssesseur, periode: ue.periode, bureaux: mpebs, tousBureaux: mpbs)
        }
        return MeProfile(id: user.id!, nom: user.nom, prenom: user.prenom, email: user.email, isAdmin: user.isAdmin, elections: mpes)
    }
}
