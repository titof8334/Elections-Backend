import Vapor

// Auth
struct LoginRequest: Content {
    let email: String
    let password: String
}

struct LoginResponse: Content {
    let token: String
    let user: UserDTO
}

struct MeResponse: Content {
    let role: String
    let bureaux: [UUID]
    let nom: String
    let prenom: String?
}

struct UserDTO: Content {
    let id: UUID
    let nom: String
    let email: String
    let role: String
    let bureaux: [UUID]
}

// Bureau
struct BureauDTO: Content {
    let id: UUID?
    let numero: Int
    let nom: String
    let adresse: String
    let inscrits: Int
    let bulletinsDepouilles: Int
    let bulletinsNuls: Int
    let bulletinsBlancs: Int
    let depouillementTermine: Bool
    let participations: [ParticipationDTO]
    let resultats: [ResultatDTO]
}

struct CreateBureauRequest: Content {
    let numero: Int
    let nom: String
    let adresse: String
    let inscrits: Int
}

struct UpdateBureauRequest: Content {
    let inscrits: Int?
    let bulletinsDepouilles: Int?
    let bulletinsNuls: Int?
    let bulletinsBlancs: Int?
    let depouillementTermine: Bool?
}

// Participation
struct ParticipationDTO: Content {
    let id: UUID?
    let bureauId: UUID
    let heure: String
    let votants: Int
    let tauxParticipation: Double
    let createdAt: Date?
    let updatedAt: Date?
}

struct UpsertParticipationRequest: Content {
    let heure: String
    let votants: Int
}

// Résultat
struct ResultatDTO: Content {
    let id: UUID?
    let bureauId: UUID
    let candidatId: UUID
    let voix: Int
    let bulletinsDepouilles: Int
    let estFinal: Bool
    let updatedAt: Date?
}

struct UpsertResultatRequest: Content {
    let candidatId: UUID
    let voix: Int
    let bulletinsDepouilles: Int
    let estFinal: Bool?
}

// Candidat
struct CandidatDTO: Content {
    let id: UUID?
    let nom: String
    let prenom: String
    let liste: String
    let couleur: String
    let ordre: Int
}

struct CreateCandidatRequest: Content {
    let nom: String
    let prenom: String
    let liste: String
    let couleur: String
    let ordre: Int
}

// Synthèse globale
struct SyntheseGlobale: Content {
    let totalInscrits: Int
    let totalVotants: Int
    let tauxParticipationGlobal: Double
    let bureaux: [BureauResume]
    let resultatsGlobaux: [ResultatGlobal]
    let participationsParHeure: [ParticipationHeure]
    let bureauxTermines: Int
    let totalBureaux: Int
}

struct BureauResume: Content {
    let id: UUID
    let numero: Int
    let nom: String
    let inscrits: Int
    let bulletinsDepouilles: Int
    let depouillementTermine: Bool
}

struct ResultatGlobal: Content {
    let candidatId: UUID
    let candidatNom: String
    let candidatPrenom: String
    let candidatListe: String
    let couleur: String
    let totalVoix: Int
    let pourcentage: Double
}

struct ParticipationHeure: Content {
    let heure: String
    let totalVotants: Int
    let tauxParticipation: Double
}

// Create user
struct CreateUserRequest: Content {
    let nom: String
    let email: String
    let password: String
    let role: String?
    let bureauIds: [UUID]?
}
