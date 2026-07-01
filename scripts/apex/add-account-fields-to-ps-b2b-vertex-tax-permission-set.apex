// API name of Permission Set to receive the permission changes
String permSetApiName = 'Vertex_Tax_Store_Custom_Fields';

// sObjectType to receive the permission changes via permission set. In this case, we are adding permissions for the Account object.
String sObjectType = 'Account';

// The custom field names to add to the permission set for the sObjectType
List<String> fieldNames = new List<String>{ 'Entity_Use_Code__c', 'Exemption_Code__c' };

// Build fully qualified field names specific to the sObjectType (e.g., Account.Entity_Use_Code__c)
List<String> fields = new List<String>();
for (String fieldName : fieldNames) {
    fields.add(sObjectType + '.' + fieldName);
}

// Locate the existing permission set by API name. If it does not exist, show an error and exit.
List<PermissionSet> permissionSets = [
    SELECT Id, Name
    FROM PermissionSet
    WHERE Name = :permSetApiName
    LIMIT 1
];

if (permissionSets.isEmpty()) {
    System.debug(LoggingLevel.ERROR,
        'Permission Set "' + permSetApiName + '" was not found. No changes were made.');
    return;
}

PermissionSet ps = permissionSets[0];

// Grant object-level access to Account.
List<ObjectPermissions> existingObjectPerms = [
    SELECT Id, ParentId, SobjectType, PermissionsRead, PermissionsEdit
    FROM ObjectPermissions
    WHERE ParentId = :ps.Id
    AND SobjectType = :sObjectType
    LIMIT 1
];

ObjectPermissions accountPerms;
if (existingObjectPerms.isEmpty()) {
    accountPerms = new ObjectPermissions(
        ParentId = ps.Id,
        SobjectType = sObjectType,
        PermissionsRead = true,
        PermissionsEdit = true
    );
} else {
    accountPerms = existingObjectPerms[0];
    accountPerms.PermissionsRead = true;
    accountPerms.PermissionsEdit = true;
}

// Permission Read Account depends on permission(s): Read Contact
// So add Contact Read as well to satisfy Salesforce dependency.
List<ObjectPermissions> existingContactPerms = [
    SELECT Id, ParentId, SobjectType, PermissionsRead, PermissionsEdit
    FROM ObjectPermissions
    WHERE ParentId = :ps.Id
    AND SobjectType = 'Contact'
    LIMIT 1
];

// Why Contact? Account and Contact have a built-in dependency in the
// permission model. You can't grant Read on Account unless the permission
// set also has Read on Contact. Salesforce enforces this when you save
// the permission set, whether through the UI, Metadata API, or Apex.
ObjectPermissions contactPerms;
if (existingContactPerms.isEmpty()) {
    contactPerms = new ObjectPermissions(
        ParentId = ps.Id,
        SobjectType = 'Contact',
        PermissionsRead = true,
        PermissionsEdit = false
    );
} else {
    contactPerms = existingContactPerms[0];
    contactPerms.PermissionsRead = true;
}

// Grant field-level access to the Account fields.
List<FieldPermissions> fieldPermsToUpsert = new List<FieldPermissions>();

for (String fieldApiName : fields) {
    List<FieldPermissions> existingFieldPerms = [
        SELECT Id, ParentId, SobjectType, Field, PermissionsRead, PermissionsEdit
        FROM FieldPermissions
        WHERE ParentId = :ps.Id
        AND Field = :fieldApiName
        LIMIT 1
    ];

    FieldPermissions fp;
    if (existingFieldPerms.isEmpty()) {
        fp = new FieldPermissions(
            ParentId = ps.Id,
            SobjectType = sObjectType,
            Field = fieldApiName,
            PermissionsRead = true,
            PermissionsEdit = true
        );
    } else {
        fp = existingFieldPerms[0];
        fp.PermissionsRead = true;
        fp.PermissionsEdit = true;
    }

    fieldPermsToUpsert.add(fp);
}

try {
    upsert contactPerms;
    upsert accountPerms;
    upsert fieldPermsToUpsert;

    System.debug(LoggingLevel.INFO,
        'Updated Permission Set "' + ps.Name + '" with Read/Edit access for ' + sObjectType + ' and fields.');

} catch (DmlException e) {
    System.debug(LoggingLevel.ERROR,
        'Failed to update Permission Set "' + permSetApiName + '".');

    for (Integer i = 0; i < e.getNumDml(); i++) {
        System.debug(LoggingLevel.ERROR, e.getDmlMessage(i));
    }
}