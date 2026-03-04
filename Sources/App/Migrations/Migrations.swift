import Fluent
import FluentKit
import FluentSQL
import Vapor

struct CreateUser: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("users")
            .id()
            .field("nom", .string, .required)
            .field("prenom", .string)
            .field("email", .string, .required)
            .field("password_hash", .string, .required)
            .field("zitadel_sub", .string)
            .field("role", .string, .required)
            .field("created_at", .datetime)
            .unique(on: "email")
            .unique(on: "zitadel_sub")
            .create()

        try await database.schema("user_bureau")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("bureau_id", .uuid, .required, .references("bureaux", "id", onDelete: .cascade))
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("user_bureau").delete()
        try await database.schema("users").delete()
    }
}

struct CreateBureau: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("bureaux")
            .id()
            .field("numero", .int, .required)
            .field("nom", .string, .required)
            .field("adresse", .string, .required)
            .field("inscrits", .int, .required)
            .field("bulletins_depouilles", .int, .required)
            .field("bulletins_nuls", .int, .required)
            .field("bulletins_blancs", .int, .required)
            .field("depouillement_termine", .bool, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("bureaux").delete()
    }
}

struct CreateParticipation: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("participations")
            .id()
            .field("bureau_id", .uuid, .required, .references("bureaux", "id", onDelete: .cascade))
            .field("heure", .string, .required)
            .field("votants", .int, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("participations").delete()
    }
}

struct CreateResultat: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("resultats")
            .id()
            .field("bureau_id", .uuid, .required, .references("bureaux", "id", onDelete: .cascade))
            .field("candidat_id", .uuid, .required)
            .field("voix", .int, .required)
            .field("bulletins_depouilles", .int, .required)
            .field("est_final", .bool, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("resultats").delete()
    }
}

struct CreateCandidat: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("candidats")
            .id()
            .field("nom", .string, .required)
            .field("prenom", .string, .required)
            .field("liste", .string, .required)
            .field("couleur", .string, .required)
            .field("ordre", .int, .required)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("candidats").delete()
    }
}

struct SeedAdminUser: AsyncMigration {
    func prepare(on database: Database) async throws {
        let hash = try Bcrypt.hash("admin123")
        let admin = User(nom: "Administrateur", email: "christ.arnal@laposte.net", passwordHash: hash, role: "admin")
        try await admin.save(on: database)
    }

    func revert(on database: Database) async throws {
        try await User.query(on: database).filter(\.$email == "christ.arnal@laposte.net").delete()
    }
}
struct AddDispFieldsToUser: AsyncMigration {
    func prepare(on database: Database) async throws {
        if database is SQLDatabase {
            // Use raw SQL for SQLite to avoid Fluent schema builder issues
            let sqlDatabase = database as! SQLDatabase
            try await sqlDatabase.raw("ALTER TABLE users ADD COLUMN disp_bureau_id TEXT").run()
            try await sqlDatabase.raw("ALTER TABLE users ADD COLUMN disp_assesseur INTEGER").run()
            try await sqlDatabase.raw("ALTER TABLE users ADD COLUMN disp_delegue INTEGER").run()
        } else {
            // Fallback for other databases
            try await database.schema("users")
                .field("disp_bureau_id", .uuid)
                .field("disp_assesseur", .bool)
                .field("disp_delegue", .bool)
                .update()
        }
    }

    func revert(on database: Database) async throws {
        if database is SQLDatabase {
            // SQLite doesn't support DROP COLUMN directly, would need table recreation
            // For now, just leave the columns (they're nullable)
        } else {
            try await database.schema("users")
                .deleteField("disp_delegue")
                .deleteField("disp_assesseur")
                .deleteField("disp_bureau_id")
                .update()
        }
    }
}

struct AddIsAdminFieldToUser: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("users")
            .field("is_admin", .bool, .required, .sql(.default(false)))
            .update()
        let user = try await User.query(on: database).filter(\.$email == "christ.arnal@laposte.net").first()
        if let user = user {
            user.isAdmin = true
            user.role = "aucun"
            try await user.save(on: database)
        }
    }

    func revert(on database: Database) async throws {
        if database is SQLDatabase {
            // SQLite doesn't support DROP COLUMN directly, would need table recreation
            // For now, just leave the columns (they're nullable)
        } else {
            try await database.schema("users")
                .deleteField("is_admin")
                .update()
        }
    }
}

