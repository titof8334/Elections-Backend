import Vapor

public func routes(_ app: Application) throws {
    // Public routes
    let publicAPI = app.grouped("api", "v1")
    try publicAPI.register(collection: PublicController())

    // Auth routes (public - no authentication required)
    let authRoutes = publicAPI.grouped("auth")
    try authRoutes.register(collection: AuthController())

    // Protected routes with Zitadel authentication
    let protected = publicAPI.grouped(ZitadelAuthMiddleware())
    try protected.register(collection: BureauController())
    try protected.register(collection: ParticipationController())
    try protected.register(collection: ResultatController())
    try protected.register(collection: AdminController())
}
