import Vapor

// Auth
struct LoginRequest: Content {
    let email: String
    let password: String
}

struct LoginResponse: Content {
    let token: String
    let user: MeResponse
}

struct MeProfile: Content {
    let id: UUID
    let nom: String
    let prenom: String?
    let email: String
    let isAdmin: Bool
    let elections: [MeProfileElection]
}
struct MeProfileElection: Content {
    let id: UUID?
    let electionId: UUID
    let nom: String
    let isOwner: Bool
    let role: String
    let dispBureauId: UUID?
    let dispDelegue: Bool
    let dispAssesseur: Bool
    let periode: String?
    let bureaux: [MeProfileElectionBureau]
    let tousBureaux: [MeProfileBureau]
}
struct MeProfileElectionBureau: Content {
    let id: UUID?
    let bureauId: UUID
    let periode: String?
}
struct MeProfileBureau: Content {
    let id: UUID?
    let numero: Int
    let nom: String
}

struct MeResponse: Content {
    let id: UUID
    let nom: String
    let prenom: String?
    let email: String
    let isAdmin: Bool
    let bureaux: [MeUserBureau]
    let elections: [ElectionDTO]
}

struct MeUserBureau: Content {
    let electionId: UUID
    let bureauId: UUID
    let periode: String?
}
/*
struct MeUserElection: Content {
    let id: UUID
    let electionId: UUID
    let nom: String
    let isOwner: Bool
    let role: String
    let isTitulaire: Bool
    let dispBureauId: UUID?
    let dispDelegue: Bool
    let dispAssesseur: Bool
    let periode: String?
}
*/
struct UserDTO: Content {
    let id: UUID?
    let nom: String?
    let prenom: String?
    let email: String?
    let isAdmin: Bool?
}

struct ElectionUserDTO: Content {
    let id: UUID?
    let nom: String?
    let prenom: String?
    let email: String
    let isAdmin: Bool?
    let isOwner: Bool?
    let role: String?
    let isTitulaire: Bool?
    let bureaux: [ElectionUserBureauDTO]?
    let dispBureauId: UUID?
    let dispAssesseur: Bool?
    let dispDelegue: Bool?
    let periode: String?
}

struct ElectionUserBureauDTO: Content {
    let id: UUID?
    let periode: String?
}
// Election
struct ElectionDTO: Content {
    let id: UUID?
    let nom: String
    let isOwner: Bool?
    let isScrutateur: Bool?
    let isSubscriber: Bool?
}

struct CreateElectionRequest: Content {
    let nom: String
}

// Bureau
struct BureauDTO: Content {
    let id: UUID?
    let numero: Int
    let nom: String
    let adresse: String
    let inscrits: Int?
    let votants: Int?
    let exprimes: Int?
    let bulletinsDepouilles: Int?
    let bulletinsNuls: Int?
    let bulletinsBlancs: Int?
    let depouillementTermine: Bool?
    let participations: [ParticipationDTO]?
    let resultats: [ResultatDTO]?
    let users: [UserBureauDTO]?
}

struct UserBureauDTO: Content {
    let id: UUID?
    let nom: String?
    let prenom: String?
    let role: String?
    let isTitulaire: Bool
    let periode: String?
    let dispAssesseur: Bool?
    let dispDelegue: Bool?
    let dispPeriode: String?
}

struct CreateBureauRequest: Content {
    let numero: Int
    let nom: String
    let adresse: String
    let inscrits: Int
}

struct UpdateBureauRequest: Content {
    let inscrits: Int?
    let numero: Int?
    let nom: String?
    let adresse: String?
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
    let updatedAt: Date?
}

struct UpsertResultatBureauRequest: Content {
    let nuls: Int
    let blancs: Int
    let bulletinsDepouilles: Int
    let resultats: [UpsertResultatBureauCandidatRequest]
    let estFinal: Bool
}
struct UpsertResultatBureauCandidatRequest: Content {
    let candidatId: UUID
    let voix: Int
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
    let totalDepouilles: Int
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
    let votants: Int
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
    let totalVoixProjete: Int
    let pourcentageProjete: Double
}

struct ParticipationHeure: Content {
    let heure: String
    let totalVotants: Int
    let tauxParticipation: Double
}

// Create user
struct CreateUserRequest: Content {
    let nom: String
    let prenom: String?
    let email: String
    let isAdmin: Bool?
}
// Update user
struct UpdateUserRequest: Content {
    let nom: String?
    let prenom: String?
    let email: String?
    let role: String?
    let isTitulaire: Bool
    let dispBureauId: UUID?
    let dispAssesseur: Bool?
    let dispDelegue: Bool?
}

struct UserElectionDTO: Content {
    let id: UUID?
    let dispBureauId: UUID?
    let dispAssesseur: Bool?
    let dispDelegue: Bool?
    let periode: String?
}
