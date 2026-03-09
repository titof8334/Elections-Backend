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
            .field("is_admin", .bool, .required, .sql(.default(false)))
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
        let admin = User(nom: "Administrateur", email: "christ.arnal@laposte.net", passwordHash: hash, isAdmin: true)
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

struct AddElection: AsyncMigration {
    func prepare(on database: Database) async throws {
//        try await database.schema("elections")
//            .id()
//            .field("nom", .string, .required)
//            .field("created_at", .datetime)
//            .field("updated_at", .datetime)
//            .create()
//        let cuers = Election(nom: "Municipales Cuers 2026")
//        try await cuers.save(on: database)
        if let cuers = try await Election.query(on: database).filter(\.$nom == "Municipales Cuers 2026").first() {
//            try await database.schema("user_election")
//                .id()
//                .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
//                .field("election_id", .uuid, .required, .references("elections", "id", onDelete: .cascade))
//                .create()
            if database is SQLDatabase {
                let sqlDatabase = database as! SQLDatabase
                
                // Add columns to user_election table
                try await sqlDatabase.raw("ALTER TABLE user_election ADD COLUMN is_owner INTEGER NOT NULL DEFAULT 0").run()
                try await sqlDatabase.raw("ALTER TABLE user_election ADD COLUMN disp_bureau_id TEXT").run()
                try await sqlDatabase.raw("ALTER TABLE user_election ADD COLUMN disp_assesseur INTEGER").run()
                try await sqlDatabase.raw("ALTER TABLE user_election ADD COLUMN disp_delegue INTEGER").run()
                try await sqlDatabase.raw("ALTER TABLE user_election ADD COLUMN periode TEXT").run()
                
                // Add columns to user_bureau table
                try await sqlDatabase.raw("ALTER TABLE user_bureau ADD COLUMN role TEXT NOT NULL DEFAULT 'aucun'").run()
                try await sqlDatabase.raw("ALTER TABLE user_bureau ADD COLUMN periode TEXT").run()
            } else {
                // Fallback for other databases
                try await database.schema("user_election")
                    .field("is_owner", .bool)
                    .field("role", .string)
                    .field("disp_bureau_id", .uuid)
                    .field("disp_assesseur", .bool)
                    .field("disp_delegue", .bool)
                    .field("periode", .string)
                    .update()
                try await database.schema("user_bureau")
                    .field("periode", .string)
                    .update()
            }
            let users = try await User.query(on: database).all()
            for user in users {
                try await cuers.$users.attach(user, on: database)
            }
            // Add election_id to candidats and bureaux using raw SQL
            if database is SQLDatabase {
                let sqlDatabase = database as! SQLDatabase
                let electionId = try cuers.requireID().uuidString
                
                // Add column as nullable first
                try await sqlDatabase.raw("ALTER TABLE candidats ADD COLUMN election_id TEXT").run()
                try await sqlDatabase.raw("ALTER TABLE bureaux ADD COLUMN election_id TEXT").run()
                
                // Update existing rows with the default election ID
                try await sqlDatabase.raw("UPDATE candidats SET election_id = '\(raw: electionId)'").run()
                try await sqlDatabase.raw("UPDATE bureaux SET election_id = '\(raw: electionId)'").run()
            } else {
                // Fallback for other databases
                try await database.schema("candidats")
                    .field("election_id", .uuid)
                    .update()
                try await database.schema("bureaux")
                    .field("election_id", .uuid)
                    .update()
            }
        } else {
            print("Cuers n'existe pas")
        }
    }

    func revert(on database: Database) async throws {
        try await database.schema("user_election").delete()
        try await database.schema("users").delete()
    }
}

struct AddElectionUsers: AsyncMigration {
    func prepare(on database: Database) async throws {
                
        // Migrate data from User to UserElection using SQL
        if database is SQLDatabase {
            let sqlDatabase = database as! SQLDatabase
            
            // Update user_election with data from users table
            try await sqlDatabase.raw("""
                UPDATE user_election
                SET 
                    is_owner = (SELECT is_admin FROM users WHERE users.id = user_election.user_id),
                    disp_bureau_id = (SELECT disp_bureau_id FROM users WHERE users.id = user_election.user_id),
                    disp_delegue = (SELECT disp_delegue FROM users WHERE users.id = user_election.user_id),
                    disp_assesseur = (SELECT disp_assesseur FROM users WHERE users.id = user_election.user_id),
                    periode = 'J'
            """).run()
        }
        try await database.schema("users")
            .deleteField("role")
            .update()
        try await database.schema("users")
            .deleteField("disp_bureau_id")
            .update()
        try await database.schema("users")
            .deleteField("disp_assesseur")
            .update()
        try await database.schema("users")
            .deleteField("disp_delegue")
            .update()
    }

    func revert(on database: Database) async throws {
        // Revert not implemented
    }
}

struct AddElectionLinks: AsyncMigration {
    func prepare(on database: Database) async throws {
        if database is SQLDatabase {
            let defElection = try await Election.query(on: database).first()
            print("SQL Base")
            let sqlDatabase = database as! SQLDatabase
            try await sqlDatabase.raw("ALTER TABLE resultats ADD COLUMN election_id TEXT").run()
            try await sqlDatabase.raw("ALTER TABLE participations ADD COLUMN election_id TEXT").run()

            try await sqlDatabase.raw("UPDATE resultats SET election_id = '\(raw: defElection?.requireID().uuidString ?? "")'").run()
            try await sqlDatabase.raw("UPDATE participations SET election_id = '\(raw: defElection?.requireID().uuidString ?? "")'").run()

        } else {
            print("no SQL Base")
            // Fallback for other databases
            try await database.schema("resultats")
                .field("election_id", .uuid)
                .update()
            try await database.schema("participations")
                .field("election_id", .uuid)
                .update()
        }
    }

    func revert(on database: Database) async throws {
        // Revert not implemented
    }
}
struct AddElectionUserBureau: AsyncMigration {
    func prepare(on database: Database) async throws {
        if database is SQLDatabase {
            let defElection = try await Election.query(on: database).first()
            let sqlDatabase = database as! SQLDatabase
            try await sqlDatabase.raw("ALTER TABLE user_bureau ADD COLUMN election_id TEXT").run()
            try await sqlDatabase.raw("UPDATE user_bureau SET election_id = '\(raw: defElection?.requireID().uuidString ?? "")'").run()

        } else {
            print("no SQL Base")
            // Fallback for other databases
            try await database.schema("user_bureau")
                .field("election_id", .uuid)
                .update()
        }
    }

    func revert(on database: Database) async throws {
        // Revert not implemented
    }
}
