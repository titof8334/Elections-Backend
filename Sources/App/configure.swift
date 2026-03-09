import Vapor
import Fluent
import FluentSQLiteDriver
import JWT

public func configure(_ app: Application) async throws {
    // Server Configuration
    app.http.server.configuration.hostname = "0.0.0.0"
    app.http.server.configuration.port = 8084
    
    // CORS
    let corsConfiguration = CORSMiddleware.Configuration(
        allowedOrigin: .all,
        allowedMethods: [.GET, .POST, .PUT, .DELETE, .PATCH, .OPTIONS],
        allowedHeaders: [.accept, .authorization, .contentType, .origin, .xRequestedWith]
    )
    app.middleware.use(CORSMiddleware(configuration: corsConfiguration))

    // JWT
    app.jwt.signers.use(.hs256(key: Environment.get("JWT_SECRET") ?? "elections-secret-key-change-in-production"))
    
    // Initialize Zitadel Service
    _ = app.zitadel

    // Database
    let dbPath = Environment.get("DB_PATH") ?? "elections.sqlite"
    app.databases.use(.sqlite(.file(dbPath)), as: .sqlite)
    app.logger.info("📦 Database: SQLite at \(dbPath)")
    // Migrations
    app.migrations.add(CreateUser())
    app.migrations.add(CreateBureau())
    app.migrations.add(CreateParticipation())
    app.migrations.add(CreateResultat())
    app.migrations.add(CreateCandidat())
    app.migrations.add(SeedAdminUser())
    app.migrations.add(AddDispFieldsToUser())
    app.migrations.add(AddElection())
    app.migrations.add(AddElectionUsers())
    app.migrations.add(AddElectionLinks())
    app.migrations.add(AddElectionUserBureau())
    // app.migrations.add(MakeElectionIdRequired()) // Décommentez quand vous voulez rendre election_id obligatoire
    try await app.autoMigrate().get()

    // Routes
    try routes(app)
}
