import Vapor

public func routes(_ app: Application) throws {
    // Public routes
    let publicAPI = app.grouped("api", "v1")
    try publicAPI.register(collection: PublicController())

    // Auth routes
    let authRoutes = publicAPI.grouped("auth")
    try authRoutes.register(collection: AuthController())

    // Protected routes
    let protected = publicAPI.grouped(JWTMiddleware())
    try protected.register(collection: BureauController())
    try protected.register(collection: ParticipationController())
    try protected.register(collection: ResultatController())
    try protected.register(collection: AdminController())
}
