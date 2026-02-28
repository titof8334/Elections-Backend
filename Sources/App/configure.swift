import Vapor
import Fluent
import FluentSQLiteDriver
import JWT

public func configure(_ app: Application) throws {
    // CORS
    let corsConfiguration = CORSMiddleware.Configuration(
        allowedOrigin: .all,
        allowedMethods: [.GET, .POST, .PUT, .DELETE, .PATCH, .OPTIONS],
        allowedHeaders: [.accept, .authorization, .contentType, .origin, .xRequestedWith]
    )
    app.middleware.use(CORSMiddleware(configuration: corsConfiguration))

    // JWT
    app.jwt.signers.use(.hs256(key: Environment.get("JWT_SECRET") ?? "elections-secret-key-change-in-production"))

    // Database
    app.databases.use(.sqlite(.file("elections.sqlite")), as: .sqlite)

    // Migrations
    app.migrations.add(CreateUser())
    app.migrations.add(CreateBureau())
    app.migrations.add(CreateParticipation())
    app.migrations.add(CreateResultat())
    app.migrations.add(CreateCandidat())
    app.migrations.add(SeedAdminUser())

    try app.autoMigrate().wait()

    // Routes
    try routes(app)
}
