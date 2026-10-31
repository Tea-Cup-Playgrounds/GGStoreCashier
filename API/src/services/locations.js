// Branches created through the legacy routes (INSERT INTO the `branches` view) have no code.
// Give them the same BRnn code the migration gave existing branches.
const assignDefaultLocationCode = async (db, locationId) => {
    await db.execute(
        "UPDATE locations SET code = CONCAT('BR', LPAD(id, 2, '0')) WHERE id = ? AND code IS NULL",
        [locationId]
    );
};

module.exports = { assignDefaultLocationCode };
