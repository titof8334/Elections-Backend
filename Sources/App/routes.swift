import Vapor

public func routes(_ app: Application) throws {
    // Public routes with optional authentication
    let publicAPI = app.grouped("api", "v1").grouped(OptionalZitadelAuthMiddleware())
    try publicAPI.register(collection: PublicController())

    // Auth routes (public - no authentication required)
    let authRoutes = publicAPI.grouped("auth")
    try authRoutes.register(collection: AuthController())

    // Protected routes with Zitadel authentication
    let protected = publicAPI.grouped(ZitadelAuthMiddleware())
    try protected.register(collection: AuthUserController())
    try protected.register(collection: DelegueController())
    try protected.register(collection: OwnerController())
    try protected.register(collection: AdminController())
}
