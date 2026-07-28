package utils

import (
	"database/sql"
	"fmt"
)

// ScenariosTable is the database table flows2fim reads reach scenarios from.
const ScenariosTable = "scenarios"

// legacyScenariosTable is the pre-0.5.0 name of ScenariosTable. It is referenced
// only to produce a helpful error for databases built by an older
// ripple1d-pipeline. It, and the branch using it in CheckScenariosTable, are
// safe to delete once no collections carrying the old schema remain in
// circulation.
const legacyScenariosTable = "rating_curves"

// tableExists reports whether the connected SQLite database has a table with
// the given name.
func tableExists(db *sql.DB, name string) (bool, error) {
	var found string
	err := db.QueryRow(`SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?;`, name).Scan(&found)
	if err == sql.ErrNoRows {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return true, nil
}

// CheckScenariosTable verifies the database exposes a 'scenarios' table, and
// returns an actionable error when it does not. A database produced by a
// ripple1d-pipeline older than the scenarios rename carries a 'rating_curves'
// table instead; that case is called out explicitly so the failure is not
// mistaken for a missing or corrupt database.
func CheckScenariosTable(db *sql.DB) error {
	ok, err := tableExists(db, ScenariosTable)
	if err != nil {
		return fmt.Errorf("error inspecting database tables: %w", err)
	}
	if ok {
		return nil
	}

	// Compatibility hint for databases predating the 0.5.0 scenarios rename. Only
	// reached once the command is already failing, so it costs nothing on the
	// success path. See legacyScenariosTable for when this can go.
	legacy, err := tableExists(db, legacyScenariosTable)
	if err != nil {
		return fmt.Errorf("error inspecting database tables: %w", err)
	}
	if legacy {
		return fmt.Errorf(
			"database has a '%[2]s' table but no '%[1]s' table. flows2fim 0.5.0 renamed this table, "+
				"because its records are computed model scenarios rather than rating curves. "+
				"Regenerate the database with a matching ripple1d-pipeline release, or rename the table in place with: "+
				"`ALTER TABLE %[2]s RENAME TO %[1]s`",
			ScenariosTable, legacyScenariosTable,
		)
	}

	return fmt.Errorf("database does not have a '%s' table", ScenariosTable)
}
