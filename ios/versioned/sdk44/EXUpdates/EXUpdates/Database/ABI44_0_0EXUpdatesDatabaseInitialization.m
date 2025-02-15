// Copyright 2021-present 650 Industries. All rights reserved.

#import <ABI44_0_0EXUpdates/ABI44_0_0EXUpdatesDatabaseInitialization+Tests.h>
#import <ABI44_0_0EXUpdates/ABI44_0_0EXUpdatesDatabaseMigration.h>
#import <ABI44_0_0EXUpdates/ABI44_0_0EXUpdatesDatabaseMigrationRegistry.h>
#import <ABI44_0_0EXUpdates/ABI44_0_0EXUpdatesDatabaseUtils.h>

NS_ASSUME_NONNULL_BEGIN

static NSString * const ABI44_0_0EXUpdatesDatabaseInitializationErrorDomain = @"ABI44_0_0EXUpdatesDatabaseInitialization";
static NSString * const ABI44_0_0EXUpdatesDatabaseLatestFilename = @"expo-v7.db";

static NSString * const ABI44_0_0EXUpdatesDatabaseInitializationLatestSchema = @"\
CREATE TABLE \"updates\" (\
\"id\"  BLOB UNIQUE,\
\"scope_key\"  TEXT NOT NULL,\
\"commit_time\"  INTEGER NOT NULL,\
\"runtime_version\"  TEXT NOT NULL,\
\"launch_asset_id\" INTEGER,\
\"manifest\"  TEXT,\
\"status\"  INTEGER NOT NULL,\
\"keep\"  INTEGER NOT NULL,\
\"last_accessed\"  INTEGER NOT NULL,\
\"successful_launch_count\"  INTEGER NOT NULL DEFAULT 0,\
\"failed_launch_count\"  INTEGER NOT NULL DEFAULT 0,\
PRIMARY KEY(\"id\"),\
FOREIGN KEY(\"launch_asset_id\") REFERENCES \"assets\"(\"id\") ON DELETE CASCADE\
);\
CREATE TABLE \"assets\" (\
\"id\"  INTEGER PRIMARY KEY AUTOINCREMENT,\
\"url\"  TEXT,\
\"key\"  TEXT UNIQUE,\
\"headers\"  TEXT,\
\"type\"  TEXT NOT NULL,\
\"metadata\"  TEXT,\
\"download_time\"  INTEGER NOT NULL,\
\"relative_path\"  TEXT NOT NULL,\
\"hash\"  BLOB NOT NULL,\
\"hash_type\"  INTEGER NOT NULL,\
\"marked_for_deletion\"  INTEGER NOT NULL\
);\
CREATE TABLE \"updates_assets\" (\
\"update_id\"  BLOB NOT NULL,\
\"asset_id\" INTEGER NOT NULL,\
FOREIGN KEY(\"update_id\") REFERENCES \"updates\"(\"id\") ON DELETE CASCADE,\
FOREIGN KEY(\"asset_id\") REFERENCES \"assets\"(\"id\") ON DELETE CASCADE\
);\
CREATE TABLE \"json_data\" (\
\"id\" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,\
\"key\" TEXT NOT NULL,\
\"value\" TEXT NOT NULL,\
\"last_updated\" INTEGER NOT NULL,\
\"scope_key\" TEXT NOT NULL\
);\
CREATE UNIQUE INDEX \"index_updates_scope_key_commit_time\" ON \"updates\" (\"scope_key\", \"commit_time\");\
CREATE INDEX \"index_updates_launch_asset_id\" ON \"updates\" (\"launch_asset_id\");\
CREATE INDEX \"index_json_data_scope_key\" ON \"json_data\" (\"scope_key\")\
";

@implementation ABI44_0_0EXUpdatesDatabaseInitialization

+ (BOOL)initializeDatabaseWithLatestSchemaInDirectory:(NSURL *)directory
                                             database:(struct sqlite3 * _Nullable * _Nonnull)database
                                                error:(NSError ** _Nullable)error
{
  return [[self class] initializeDatabaseWithLatestSchemaInDirectory:directory
                                                            database:database
                                                          migrations:[ABI44_0_0EXUpdatesDatabaseMigrationRegistry migrations]
                                                               error:error];
}

+ (BOOL)initializeDatabaseWithLatestSchemaInDirectory:(NSURL *)directory
                                             database:(struct sqlite3 * _Nullable * _Nonnull)database
                                           migrations:(NSArray<id<ABI44_0_0EXUpdatesDatabaseMigration>> *)migrations
                                                error:(NSError ** _Nullable)error
{
  return [[self class] initializeDatabaseWithSchema:ABI44_0_0EXUpdatesDatabaseInitializationLatestSchema
                                           filename:ABI44_0_0EXUpdatesDatabaseLatestFilename
                                        inDirectory:directory
                                      shouldMigrate:YES
                                         migrations:migrations
                                           database:database
                                              error:error];
}

+ (BOOL)initializeDatabaseWithSchema:(NSString *)schema
                            filename:(NSString *)filename
                         inDirectory:(NSURL *)directory
                       shouldMigrate:(BOOL)shouldMigrate
                          migrations:(NSArray<id<ABI44_0_0EXUpdatesDatabaseMigration>> *)migrations
                            database:(struct sqlite3 * _Nullable * _Nonnull)database
                               error:(NSError ** _Nullable)error
{
  sqlite3 *db;
  NSURL *dbUrl = [directory URLByAppendingPathComponent:filename];
  BOOL shouldInitializeDatabaseSchema = ![[NSFileManager defaultManager] fileExistsAtPath:[dbUrl path]];

  BOOL success = [[self class] _migrateDatabaseInDirectory:directory withMigrations:migrations];
  if (!success) {
    NSError *removeFailedMigrationError;
    if ([NSFileManager.defaultManager fileExistsAtPath:dbUrl.path] &&
        ![NSFileManager.defaultManager removeItemAtPath:dbUrl.path error:&removeFailedMigrationError]) {
      if (error != nil) {
        NSString *description = [NSString stringWithFormat:@"Failed to migrate database, then failed to remove old database file: %@", removeFailedMigrationError.localizedDescription];
        *error = [NSError errorWithDomain:ABI44_0_0EXUpdatesDatabaseInitializationErrorDomain
                                     code:1022
                                 userInfo:@{ NSLocalizedDescriptionKey: description, NSUnderlyingErrorKey: removeFailedMigrationError }];
      }
      return NO;
    }
    shouldInitializeDatabaseSchema = YES;
  } else {
    shouldInitializeDatabaseSchema = NO;
  }

  int resultCode = sqlite3_open([[dbUrl path] UTF8String], &db);
  if (resultCode != SQLITE_OK) {
    NSLog(@"Error opening SQLite db: %@", [ABI44_0_0EXUpdatesDatabaseUtils errorFromSqlite:db].localizedDescription);
    sqlite3_close(db);

    if (resultCode == SQLITE_CORRUPT || resultCode == SQLITE_NOTADB) {
      NSString *archivedDbFilename = [NSString stringWithFormat:@"%f-%@", [[NSDate date] timeIntervalSince1970], filename];
      NSURL *destinationUrl = [directory URLByAppendingPathComponent:archivedDbFilename];
      NSError *err;
      if ([[NSFileManager defaultManager] moveItemAtURL:dbUrl toURL:destinationUrl error:&err]) {
        NSLog(@"Moved corrupt SQLite db to %@", archivedDbFilename);
        if (sqlite3_open([[dbUrl absoluteString] UTF8String], &db) != SQLITE_OK) {
          if (error != nil) {
            *error = [ABI44_0_0EXUpdatesDatabaseUtils errorFromSqlite:db];
          }
          return NO;
        }
        shouldInitializeDatabaseSchema = YES;
      } else {
        NSString *description = [NSString stringWithFormat:@"Could not move existing corrupt database: %@", [err localizedDescription]];
        if (error != nil) {
          *error = [NSError errorWithDomain:ABI44_0_0EXUpdatesDatabaseInitializationErrorDomain
                                       code:1004
                                   userInfo:@{ NSLocalizedDescriptionKey: description, NSUnderlyingErrorKey: err }];
        }
        return NO;
      }
    } else {
      if (error != nil) {
        *error = [ABI44_0_0EXUpdatesDatabaseUtils errorFromSqlite:db];
      }
      return NO;
    }
  }

  // foreign keys must be turned on explicitly for each database connection
  NSError *pragmaForeignKeysError;
  if (![ABI44_0_0EXUpdatesDatabaseUtils executeSql:@"PRAGMA foreign_keys=ON;" withArgs:nil onDatabase:db error:&pragmaForeignKeysError]) {
    NSLog(@"Error turning on foreign key constraint: %@", pragmaForeignKeysError.localizedDescription);
  }

  if (shouldInitializeDatabaseSchema) {
    char *errMsg;
    if (sqlite3_exec(db, schema.UTF8String, NULL, NULL, &errMsg) != SQLITE_OK) {
      if (error != nil) {
        *error = [ABI44_0_0EXUpdatesDatabaseUtils errorFromSqlite:db];
      }
      sqlite3_free(errMsg);
      return NO;
    };
  }

  *database = db;
  return YES;
}

+ (BOOL)_migrateDatabaseInDirectory:(NSURL *)directory withMigrations:(NSArray<id<ABI44_0_0EXUpdatesDatabaseMigration>> *)migrations
{
  NSURL *latestURL = [directory URLByAppendingPathComponent:ABI44_0_0EXUpdatesDatabaseLatestFilename];
  if ([NSFileManager.defaultManager fileExistsAtPath:latestURL.path]) {
    return YES;
  }

  // find the newest database version that exists and try to migrate that file (ignore any older ones)
  __block NSURL *existingURL;
  __block NSUInteger startingMigrationIndex;
  [migrations enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(id<ABI44_0_0EXUpdatesDatabaseMigration> migration, NSUInteger idx, BOOL *stop) {
    NSURL *possibleURL = [directory URLByAppendingPathComponent:migration.filename];
    if ([NSFileManager.defaultManager fileExistsAtPath:possibleURL.path]) {
      existingURL = possibleURL;
      startingMigrationIndex = idx;
      *stop = YES;
    }
  }];

  if (existingURL) {
    NSError *fileMoveError;
    if (![NSFileManager.defaultManager moveItemAtPath:existingURL.path toPath:latestURL.path error:&fileMoveError]) {
      NSLog(@"Migration failed: failed to rename database file");
      return NO;
    }
    sqlite3 *db;
    if (sqlite3_open(latestURL.absoluteString.UTF8String, &db) != SQLITE_OK) {
      NSLog(@"Error opening migrated SQLite db: %@", [ABI44_0_0EXUpdatesDatabaseUtils errorFromSqlite:db].localizedDescription);
      sqlite3_close(db);
      return NO;
    }

    for (NSUInteger i = startingMigrationIndex; i < migrations.count; i++) {
      NSError *migrationError;
      id<ABI44_0_0EXUpdatesDatabaseMigration> migration = migrations[i];
      if (![migration runMigrationOnDatabase:db error:&migrationError]) {
        NSLog(@"Error migrating SQLite db: %@", [ABI44_0_0EXUpdatesDatabaseUtils errorFromSqlite:db].localizedDescription);
        sqlite3_close(db);
        return NO;
      }
    }

    // migration was successful
    sqlite3_close(db);
    return YES;
  }
  return NO;
}

@end

NS_ASSUME_NONNULL_END
