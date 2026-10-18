import SwiftData

enum FreshVisionSchemaV1: VersionedSchema {
  static let versionIdentifier = Schema.Version(1, 0, 0)
  static var models: [any PersistentModel.Type] { [ScanRecord.self] }
}

enum FreshVisionMigrationPlan: SchemaMigrationPlan {
  static var schemas: [any VersionedSchema.Type] { [FreshVisionSchemaV1.self] }
  static var stages: [MigrationStage] { [] }
}
