public class Fake {
	private static FakeId fakeId = new FakeId();
	private SObjectType sobjType;
	private String relationshipName = '';
	private Map<String, Object> fieldValByName = new Map<String, Object>();
	private Map<ChildRelationshipKey, FakeChildren> fakeChildrenByChildRelationshipKey = new Map<ChildRelationshipKey, FakeChildren>();
	private Map<String, Fake> parentFakeByLookupName = new Map<String, Fake>();

	private Map<String, ChildRelationship> childRelationshipByName {
		get {
			if (childRelationshipByName == null) {
				childRelationshipByName = this.getChildRelationshipByName();
			}
			return childRelationshipByName;
		}
		set;
	}

	private Map<String, RecordTypeInfo> rtInfoByName {
		get {
			if (rtInfoByName == null) {
				rtInfoByName = this.sobjType.getDescribe().getRecordTypeInfosByName();
			}
			return rtInfoByName;
		}
		set;
	}

	private Map<String, RecordTypeInfo> rtInfoByDevName {
		get {
			if (rtInfoByDevName == null) {
				rtInfoByDevName = this.sobjType.getDescribe().getRecordTypeInfosByDeveloperName();
			}
			return rtInfoByDevName;
		}
		set;
	}

	public Fake(Type type) {
		this(((SObject)type.newInstance()).getSObjectType());
	}

	public Fake(SObjectType sobjType) {
		this.sobjType = sobjType;
		this.putAttributes();
		this.putId();
	}

	private Fake(SObject sobj) {
		this.sobjType = sobj.getSObjectType();
		this.fieldValByName = sobj.getPopulatedFieldsAsMap().clone();
		for (String relName : childRelationshipByName.keySet()) {
			this.fieldValByName.remove(relName);
		}
	}

	public Fake putRecordTypeByName(String rtName) {
		RecordTypeInfo rtInfo = rtInfoByName.get(rtName);
		if (rtInfo == null) {
			throw new InvalidRecordTypeException('RT with Name ' + '\'' + rtName + '\'' + ' doesn\'t exist for SObject: ' + this.sobjType);
		}
		this.putRecordType(rtInfo);
		return this.putField('RecordTypeId', rtInfo.getRecordTypeId());
	}

	public Fake putRecordTypeByDevName(String rtDevName) {
		RecordTypeInfo rtInfo = rtInfoByDevName.get(rtDevName);
		if (rtInfo == null) {
			throw new InvalidRecordTypeException('RT with Developer Name ' + '\'' + rtDevName + '\'' + ' doesn\'t exist for SObject: ' + this.sobjType);
		}
		this.putRecordType(rtInfo);
		return this.putField('RecordTypeId', rtInfo.getRecordTypeId());
	}

	public Fake putField(String fieldName, Object fieldValue) {
		this.checkAndGetSObjectField(fieldName);
		this.fieldValByName.put(fieldName, fieldValue);
		return this;
	}

	public Fake putField(SObjectField field, Object fieldValue) {
		String fieldName = field.getDescribe().getName();
		return putField(fieldName, fieldValue);
	}

	public Fake putParent(String lookupFieldName, SObject sobj) {
		return this.putParent(lookupFieldName, new Fake(sobj));
	}

	public Fake putParent(String lookupFieldName, Fake parentFake) {
		this.checkAndGetParentRelationshipName(lookupFieldName);
		this.parentFakeByLookupName.put(lookupFieldName, parentFake);
		return this;
	}

	public Fake putChildren(String childRelationshipName, List<SObject> sObjects) {
		for (SObject sobj : sObjects) {
			this.putChild(childRelationshipName, sobj);
		}
		return this;
	}

	public Fake putChild(String childRelationshipName, SObject sobj) {
		this.putChild(childRelationshipName, new Fake(sobj));
		return this;
	}

	public Fake putChild(String childRelationshipName, Fake childFake) {
		this.checkAndGetChildRelationship(childRelationshipName);
		String parentRelationshipName = this.getParentFieldFromChildRelationship(childRelationshipName);
		this.populateFakeChildrenMap(parentRelationshipName, childRelationshipName, childFake);
		return this;
	}

	public SObject build() {
		//add children
		this.fieldValByName.putAll(this.getChildrenToBuild());
		//add parents
		this.fieldValByName.putAll(this.getParentsToBuild());
		String serializedSObject = JSON.serialize(this.fieldValByName);
		return (SObject) JSON.deserialize(serializedSObject, Type.forName(sobjType.getDescribe().getName()));
	}

	public Fake preview() {
		System.debug('\nPreview => ' + this);
		return this;
	}

	public override String toString() {
		return 'Fake SObjectType: ' + this.sobjType.getDescribe().getName() + ',\n' +
			' relationshipName : ' + this.relationshipName + ',\n' +
			' fieldValByName : ' + JSON.serializePretty(this.fieldValByName) + ',\n' +
			' parentFakeByLookupName : ' + this.parentFakeByLookupName + ',\n' +
			' fakeChildrenByChildRelationshipKey : ' + this.fakeChildrenByChildRelationshipKey
			;
	}

	private Fake putAttributes() {
		this.fieldValByName.put(
			'attributes'
			, new Map<String, String>{
				'type' => this.sobjType.getDescribe().getName()
			});

		return this;
	}

	private Fake putId() {
		if ( ! this.fieldValByName.containsKey('Id')) {
			putField('Id', fakeId.generate(this.sobjType));
		}
		return this;
	}

	private Fake putRecordType(RecordTypeInfo rtInfo) {
		this.fieldValByName.put('RecordType', new Map<String, Object> {
			'attributes' => new Map<String, Object>{ 'type' => 'RecordType' }
			,	'Id' => rtInfo.getRecordTypeId()
			,	'DeveloperName' => rtInfo.getDeveloperName()
			,	'Name' => rtInfo.getName()
		});
		return this;
	}

	private void putParentId(String parentFieldName, Fake childFake) {
		childFake.putField(parentFieldName, this.fieldValByName.get('Id'));
	}

	private void populateFakeChildrenMap(String parentRelationshipName, String childRelationshipName, Fake child) {
		ChildRelationshipKey key = new ChildRelationshipKey(childRelationshipName, parentRelationshipName);
		if (this.fakeChildrenByChildRelationshipKey.containsKey(key)) {
			this.fakeChildrenByChildRelationshipKey.get(key).addFakeChild(child);
		} else {
			this.fakeChildrenByChildRelationshipKey.put(key, new FakeChildren(childRelationshipName, child));
		}
	}

	private Map<String, Object> getChildrenToBuild() {
		Map<String, Object> childByRelationshipName = new Map<String, Object>();
		for (ChildRelationshipKey key : this.fakeChildrenByChildRelationshipKey.keySet()) {  // Map<String, FakeChildren>
			Map<String, Object> fieldValByName = new Map<String, Object>();
			List<Map<String, Object>> children = new List<Map<String, Object>>();
			FakeChildren fakeChildren = this.fakeChildrenByChildRelationshipKey.get(key);
			for (Fake fakeChild : fakeChildren.fakes) {
				this.putParentId(key.parentFieldNameForChild, fakeChild);
				children.add(fakeChild.fieldValByName);
			}
			fieldValByName.put('totalSize', children.size());
			fieldValByName.put('done', true);
			fieldValByName.put('records', children);
			childByRelationshipName.put(fakeChildren.childRelationshipName, fieldValByName);
		}
		return childByRelationshipName;
	}

	private Map<String, Object> getParentsToBuild() {
		Map<String, Object> parentByRelationshipName = new Map<String, Object>();
		for (String lookupFieldName : this.parentFakeByLookupName.keySet()) {
			Fake parentFake = this.parentFakeByLookupName.get(lookupFieldName);
			this.putField(lookupFieldName, (String) parentFake.fieldValByName.get('Id'));
			if ( ! parentFake.parentFakeByLookupName.isEmpty()) {
				parentFake.fieldValByName.putAll(parentFake.getParentsToBuild());
			}
			parentByRelationshipName.put(this.checkAndGetParentRelationshipName(lookupFieldName), parentFake.fieldValByName);
		}
		return parentByRelationshipName;
	}

	private String getParentFieldFromChildRelationship(String childRelationshipName) {
		ChildRelationship relationship = this.checkAndGetChildRelationship(childRelationshipName);
		return relationship.getField().getDescribe().getName();
	}

	private Map<String, ChildRelationship> getChildRelationshipByName() {
		Map<String, ChildRelationship> childRelationshipByName = new Map<String, ChildRelationship>();
		List<ChildRelationship> childRelationships = this.sobjType.getDescribe().getChildRelationships();
		for (ChildRelationship relationship : childRelationships) {
			childRelationshipByName.put(relationship.getRelationshipName(), relationship);
		}
		childRelationshipByName.remove(null);
		return childRelationshipByName;
	}

	private ChildRelationship checkAndGetChildRelationship(String childRelationshipName) {
		ChildRelationship relationship = this.childRelationshipByName.get(childRelationshipName);
		if (relationship == null) {
			throw new InvalidChildRelationshipException(this.sobjType + ' doesn\'t contain Child Relationship with name ' + '\'' + childRelationshipName + '\'');
		}
		return relationship;
	}

	private String checkAndGetParentRelationshipName(String fieldName) {
		SObjectField field = this.checkAndGetSObjectField(fieldName);
		if (field.getDescribe().getType() != DisplayType.REFERENCE) {
			throw new InvalidFieldException('Field with name ' + '\'' + fieldName + '\' is not a lookup field for SObject ' + this.sobjType);
		}
		return field.getDescribe().getRelationshipName();
	}

	private SObjectField checkAndGetSObjectField(String fieldName) {
		Map<String, SObjectField> fieldByName = this.sobjType.getDescribe().fields.getMap();
		SObjectField field = fieldByName.get(fieldName);
		if (field == null) {
			throw new InvalidFieldException(this.sobjType + ' has not field with name ' + '\'' + fieldName + '\'');
		}
		return field;
	}

	private class ChildRelationshipKey {
		private String childRelationship;
		private String parentFieldNameForChild;

		private ChildRelationshipKey(String childRelationship, String parentFieldNameForChild) {
			this.childRelationship = childRelationship;
			this.parentFieldNameForChild = parentFieldNameForChild;
		}

		private Boolean equals(Object obj) {
			if (obj instanceof ChildRelationshipKey) {
				ChildRelationshipKey chrKey = (ChildRelationshipKey) obj;
				return this.childRelationship.equalsIgnoreCase(chrKey.childRelationship) &&
					this.parentFieldNameForChild.equalsIgnoreCase(chrKey.parentFieldNameForChild);
			}
			return false;
		}

		private Integer hashCode() {
			return (31 * this.childRelationship.hashCode()) ^ (this.parentFieldNameForChild.hashCode());
		}

	}

	private class FakeId {
		private Integer fakeIdCount = 0;
		private final String ID_PATTERN = '000000000000';

		private Id generate(SObjectType sobjType) {
			fakeIdCount++;
			String keyPrefix = sobjType.getDescribe().getKeyPrefix();
			String fakeIdPrefix = ID_PATTERN.substring(0, 12 - fakeIdCount.format().length());
			return Id.valueOf(keyPrefix + fakeIdPrefix + fakeIdCount);
		}
	}

	private class FakeChildren {
		private String childRelationshipName;
		private List<Fake> fakes = new List<Fake>();

		private FakeChildren(String childRelationshipName, Fake child) {
			this.childRelationshipName = childRelationshipName;
			this.fakes.add(child);
		}

		private void addFakeChild(Fake child) {
			this.fakes.add(child);
		}
	}

	public abstract class FakeException extends Exception {}
	public class InvalidRecordTypeException extends FakeException {}
	public class InvalidChildRelationshipException extends FakeException {}
	public class InvalidFieldException extends FakeException {}

}