// What the signed-in user may do, per location. Mirrors `Access` in API/src/services/access.js;
// the API re-checks every request, this only decides what the UI offers.

export interface Assignment {
  locationId: number | null; // null = every location
  locationName: string | null;
  locationType: 'branch' | 'warehouse' | null;
  roleId: number;
  roleCode: string | null;
  roleName: string;
  permissions: string[];
}

export interface AccessJson {
  isOwner: boolean;
  assignments: Assignment[];
}

export class Access {
  readonly isOwner: boolean;
  readonly assignments: Assignment[];

  constructor(json: AccessJson) {
    this.isOwner = json.isOwner;
    this.assignments = json.assignments;
  }

  /** With a location: may the user do this there? Without: anywhere? */
  can(permission: string, locationId?: number | null): boolean {
    if (this.isOwner) return true;
    return this.assignments.some(
      (a) =>
        a.permissions.includes(permission) &&
        (locationId === undefined || locationId === null || a.locationId === null || a.locationId === locationId),
    );
  }

  canAny(...permissions: string[]): boolean {
    return permissions.some((p) => this.can(p));
  }

  /** Location ids where the user holds the permission, or null for "every location". */
  locationsFor(permission: string): number[] | null {
    if (this.isOwner) return null;
    const matching = this.assignments.filter((a) => a.permissions.includes(permission));
    if (matching.some((a) => a.locationId === null)) return null;
    return [...new Set(matching.map((a) => a.locationId as number))];
  }

  /** Union of locationsFor() over several permissions: null if any of them covers every location. */
  locationsForAny(...permissions: string[]): number[] | null {
    const ids = new Set<number>();
    for (const permission of permissions) {
      const scope = this.locationsFor(permission);
      if (scope === null) return null;
      scope.forEach((id) => ids.add(id));
    }
    return [...ids];
  }

  get roleLabel(): string {
    if (this.isOwner) return 'Owner';
    const names = [...new Set(this.assignments.map((a) => a.roleName))];
    return names.length ? names.join(' · ') : 'Tanpa akses';
  }
}
