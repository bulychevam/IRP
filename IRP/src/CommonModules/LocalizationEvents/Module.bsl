// @strict-types

#Region Public

// Find data for input string choice data get processing.
//
// Parameters:
//  Source - CatalogManagerCatalogName, ChartOfCharacteristicTypesManagerChartOfCharacteristicTypesName - Source
//  ChoiceData - ValueList - Choice data
//  Parameters - Structure - Parameters:
//  * SearchString - String - Search string
//  * Filter - Structure - Filter:
//  	** CustomSearchFilter - String - Serialized array
//  	** Key - String - Key
//  	** Value - String - Value
//  StandardProcessing - Boolean - Standard processing
Procedure FindDataForInputStringChoiceDataGetProcessing(Source, ChoiceData, Parameters, StandardProcessing) Export

	If Not StandardProcessing Or Not ValueIsFilled(Parameters.SearchString) Then
		Return;
	EndIf;
	
	// Cut last symblos if it came from Excel
	If StrEndsWith(Parameters.SearchString, "¶") Then 
		Parameters.SearchString = Left(Parameters.SearchString, StrLen(Parameters.SearchString) - 1);
	EndIf;

	StandardProcessing = False;

	MetadataObject = Source.EmptyRef().Metadata();
	Settings = New Structure();
	Settings.Insert("MetadataObject", MetadataObject);
	Settings.Insert("Filter", "");
	QueryBuilderText = CommonFormActionsServer.QuerySearchInputByString(Settings);

	QueryBuilder = New QueryBuilder(QueryBuilderText);
	QueryBuilder.FillSettings();

	UserSettingFilterParameters = New Structure();
	UserSettingFilterParameters.Insert("AttributeName",
		UserSettingsServer.GetPredefinedUserSettingNames().USE_OBJECT_WITH_DELETION_MARK);
	UserSettingFilterParameters.Insert("MetadataObject", Source.EmptyRef().Metadata());
	UserSettings = UserSettingsServer.GetUserSettings(Undefined, UserSettingFilterParameters);

	UseObjectWithDeletionMark = True;
	If UserSettings.Count() Then
		// @skip-check invocation-parameter-type-intersect
		UseObjectWithDeletionMark = Boolean(UserSettings[0].Value);
	EndIf;

	If Not UseObjectWithDeletionMark Then
		NewFilter = QueryBuilder.Filter.Add("Ref.DeletionMark");
		NewFilter.Use = True;
		NewFilter.ComparisonType = ComparisonType.NotEqual;
		NewFilter.Value = True;
	EndIf;

	For Each Filter In Parameters.Filter Do
		FilterKey = Filter.Key; // String
		If Upper(FilterKey) = Upper("CustomSearchFilter") Then
			ArrayOfFilters = CommonFunctionsServer.DeserializeXMLUseXDTO(Parameters.Filter.CustomSearchFilter); // Array of see NewCustomSearchFilter
			For Each FilterRow In ArrayOfFilters Do
				NewFilter = QueryBuilder.Filter.Add("Ref." + FilterRow.FieldName);
				NewFilter.Use = True;
				NewFilter.ComparisonType = FilterRow.ComparisonType;
				NewFilter.Value = FilterRow.Value;
			EndDo;
		Else
			NewFilter = QueryBuilder.Filter.Add("Ref." + Filter.Key);
			NewFilter.Use = True;
			NewFilter.ComparisonType = ComparisonType.Equal;
			NewFilter.Value = Filter.Value;
		EndIf;
	EndDo;
	AccessSymbols = ".,- ¶" + Chars.LF + Chars.NBSp + Chars.CR;
	SearchStringNumber = CommonFunctionsClientServer.GetNumberPartFromString(Parameters.SearchString, AccessSymbols);

	Query = QueryBuilder.GetQuery();
	Query.SetParameter("SearchStringNumber", SearchStringNumber);
	Query.SetParameter("SearchString", Parameters.SearchString);
	QueryTable = GetItemsBySearchString(Query);

	ChoiceData = New ValueList();

	For Each Row In QueryTable Do
		If Not ChoiceData.FindByValue(Row.Ref) = Undefined Then
			Continue;
		EndIf;
		
		If Row.Sort = 0 Then
			ChoiceData.Add(Row.Ref, "[" + Row.Ref.Code + "] " + Row.Presentation, False, PictureLib.AddToFavorites);
		ElsIf Row.Sort = 1 Then
			If IsBlankString(Row.Ref.ItemID) Then
				ChoiceData.Add(Row.Ref, Row.Presentation, False, PictureLib.Price);
			Else
				ChoiceData.Add(Row.Ref, "(" + Row.Ref.ItemID + ") " + Row.Presentation, False, PictureLib.Price);
			EndIf;
		Else
			ChoiceData.Add(Row.Ref, Row.Presentation);
		EndIf;
	EndDo;
EndProcedure

// Get items by search string.
//
// Parameters:
//  Query - Query - Query
//
// Returns:
//  ValueTable - Get items by search string:
//		* Ref - CatalogRef.Items
//		* Presentation - String
Function GetItemsBySearchString(Query)
	Return Query.Execute().Unload();
EndFunction

// Replace description localization prefix.
//
// Parameters:
//  QueryText - String - Query text
//  TableName - String - Table name
//
// Returns:
//  String - Replace description localization prefix
Function ReplaceDescriptionLocalizationPrefix(QueryText, TableName = "Table") Export
	QueryField = "CASE WHEN %1.Description_%2 = """" THEN %1.Description_en ELSE %1.Description_%2 END ";
	QueryField = StrTemplate(QueryField, TableName, LocalizationReuse.GetLocalizationCode());
	Return StrReplace(QueryText, StrTemplate("%1.Description_en", TableName), QueryField);
EndFunction

// Get catalog presentation.
//
// Parameters:
//  Source - CatalogManager, ChartOfCharacteristicTypesManager - Source
//  Data - Structure - Data:
//  	* Code - String, Number - Code
//  	* Ref - CatalogRefCatalogName
//  	* Description - String
//  	* FullDescription - String
//  Presentation - String - Presentation
//  StandardProcessing - Boolean - Standard processing
Procedure GetCatalogPresentation(Source, Data, Presentation, StandardProcessing) Export
	If Not StandardProcessing Then
		Return;
	EndIf;
	StandardProcessing = False;
	SourceType = TypeOf(Source);
	If SourceType = Type("CatalogManager.Currencies") Then
		Presentation = String(Data.Code);
	ElsIf SourceType = Type("ChartOfAccountsManager.R6010C_Master") Then
		Presentation = String(Data.Code);
	ElsIf SourceType = Type("CatalogManager.PriceKeys") Then
		Presentation = LocalizationReuse.CatalogDescriptionWithAddAttributes(Data.Ref);
		If IsBlankString(Presentation) Then
			Presentation = StrTemplate(R().Error_005, LocalizationReuse.UserLanguageCode());
		EndIf;
	ElsIf Data.Property("Description") Then
		Presentation = String(Data.Description);
	ElsIf Data.Property("FullDescription") Then
		Presentation = String(Data.FullDescription);
	Else
		Presentation = String(Data["Description_" + LocalizationReuse.UserLanguageCode()]);
		If Presentation = "" Then
			For Each KeyData In Data Do
				If KeyData.Value = "" Then
					Continue;
				EndIf;
				Presentation = String(KeyData.Value);
				Break;
			EndDo;

			If Presentation = "" Then
				Presentation = StrTemplate(R().Error_002, LocalizationReuse.UserLanguageCode());
			EndIf;
		EndIf;
	EndIf;
EndProcedure

// Refresh reusable values before write.
//
// Parameters:
//  Source - CatalogObjectCatalogName, ChartOfCharacteristicTypesObjectChartOfCharacteristicTypesName - Source
//  Cancel - Boolean - Cancel
Procedure RefreshReusableValuesBeforeWrite(Source, Cancel) Export
	RefreshReusableValues();
EndProcedure

// Create main form item description.
//
// Parameters:
//  Form - ClientApplicationForm - Form
//  GroupName - String - Group name
//  AddInfo - Undefined, Structure - Add info
Procedure CreateMainFormItemDescription(Form, GroupName, AddInfo = Undefined) Export
	ParentGroup = Form.Items.Find(GroupName); // FormGroup, FormGroupExtensionForAUsualGroup
	ParentGroup.Group = ChildFormItemsGroup.Vertical;

	If ParentGroup = Undefined Then
		Return;
	EndIf;

	LocalizationCode = LocalizationReuse.GetLocalizationCode();
	If Upper(TrimAll(LocalizationCode)) <> Upper(TrimAll("en")) Then
		NewAttribute = Form.Items.Add("Description_en", Type("FormField"), ParentGroup);
		NewAttribute.Type = FormFieldType.LabelField;
		NewAttribute.Hyperlink = True;
		NewAttribute.DataPath = "Object.Description_en";
		NewAttribute.SetAction("Click", "DescriptionOpening");
	EndIf;

	For Each Attribute In LocalizationReuse.AllDescription() Do
		If Form.Items.Find(Attribute) <> Undefined Then
			Continue;
		EndIf;

		If StrEndsWith(Attribute, LocalizationCode) Then
			NewAttribute = Form.Items.Add(Attribute, Type("FormField"), ParentGroup);
			NewAttribute.Type = FormFieldType.InputField;
			NewAttribute.DataPath = "Object." + Attribute;
			NewAttribute.OpenButton = True;
			NewAttribute.AutoMarkIncomplete = True;
			NewAttribute.SetAction("Opening", "DescriptionOpening");
		EndIf;
	EndDo;
EndProcedure

// Create sub form item description.
//
// Parameters:
//  Form - ClientApplicationForm - Form
//  Values - Structure - All lang description
//  GroupName - String - Group name
//  AddInfo - Undefined - Add info
Procedure CreateSubFormItemDescription(Form, Values, GroupName, AddInfo = Undefined) Export
	ParentGroup = Form.Items.Find(GroupName); // FormGroup, FormGroupExtensionForAUsualGroup
	ParentGroup.Group = ChildFormItemsGroup.Vertical;

	If ParentGroup = Undefined Then
		Return;
	EndIf;

	AttributeNames = LocalizationReuse.AllDescription();

	ArrayOfNewFormAttributes = New Array();

	For Each AttributeName In AttributeNames Do
		MetadataValue = Metadata.CommonAttributes[AttributeName];

		ArrayOfNewFormAttributes.Add(New FormAttribute(MetadataValue.Name, MetadataValue.Type, , String(MetadataValue),
			True));
	EndDo;

	Form.ChangeAttributes(ArrayOfNewFormAttributes);

	For Each AttributeName In AttributeNames Do
		MetadataValue = Metadata.CommonAttributes[AttributeName];
		If Form.Items.Find(AttributeName) = Undefined Then
			NewAttribute = Form.Items.Add(MetadataValue.Name, Type("FormField"), ParentGroup);
			NewAttribute.Type = FormFieldType.InputField;
			NewAttribute.DataPath = MetadataValue.Name;

			Form[MetadataValue.Name] = Values[MetadataValue.Name];
		EndIf;
	EndDo;
EndProcedure

// Get catalog presentation fields presentation fields get processing.
//
// Parameters:
//  Source - CatalogManagerCatalogName, ChartOfCharacteristicTypesManagerChartOfCharacteristicTypesName - Source
//  Fields - Array - Fields
//  StandardProcessing - Boolean - Standard processing
Procedure GetCatalogPresentationFieldsPresentationFieldsGetProcessing(Source, Fields, StandardProcessing) Export
	If Not StandardProcessing Then
		Return;
	EndIf;
	StandardProcessing = False;
	Fields = LocalizationServer.FieldsListForDescriptions(String(Source));
EndProcedure

// Before write descriptions check filling.
//
// Parameters:
//  Source - CatalogObjectCatalogName, ChartOfCharacteristicTypesObjectChartOfCharacteristicTypesName, ExchangePlanObjectExchangePlanName - Source
//  Cancel - Boolean - Cancel
Procedure BeforeWrite_DescriptionsCheckFilling(Source, Cancel) Export
	If Source.DataExchange.Load Then
		Return;
	EndIf;
	CheckDescriptionFilling(Source, Cancel);
	CheckDescriptionDuplicate(Source, Cancel);
EndProcedure

// Fill check processing description check filling.
//
// Parameters:
//  Source - CatalogObjectCatalogName, ChartOfCharacteristicTypesObjectChartOfCharacteristicTypesName, ExchangePlanObjectExchangePlanName - Source
//  Cancel - Boolean - Cancel
//  CheckedAttributes - Array - Checked attributes
Procedure FillCheckProcessing_DescriptionCheckFilling(Source, Cancel, CheckedAttributes) Export
	CheckDescriptionFilling(Source, Cancel);
	CheckDescriptionDuplicate(Source, Cancel);
EndProcedure

#EndRegion

#Region Private

// Check description filling.
//
// Parameters:
//  Source - CatalogObjectCatalogName, ChartOfCharacteristicTypesObjectChartOfCharacteristicTypesName, ExchangePlanObjectExchangePlanName - Source
//  Cancel - Boolean - Cancel
Procedure CheckDescriptionFilling(Source, Cancel)
	If Cancel Then
		Return;
	EndIf;

	If Not CatConfigurationMetadataServer.CheckDescriptionFillingEnabled(Source)
		Or Not LocalizationReuse.UseMultiLanguage(Source.Metadata().FullName()) Then
		Return;
	EndIf;

	IsFilledDescription = False;
	For Each Attribute In LocalizationReuse.AllDescription() Do
		If ValueIsFilled(Source[Attribute]) Then
			IsFilledDescription = True;
			Break;
		EndIf;
	EndDo;
	If Not IsFilledDescription Then
		Cancel = True;
		CommonFunctionsClientServer.ShowUsersMessage(R().Error_003);
	EndIf;
EndProcedure

// Check description duplicate.
//
// Parameters:
//  Source - CatalogObjectCatalogName, ChartOfCharacteristicTypesObjectChartOfCharacteristicTypesName, ExchangePlanObjectExchangePlanName - Source
//  Cancel - Boolean - Cancel
Procedure CheckDescriptionDuplicate(Source, Cancel)
	If Cancel Then
		Return;
	EndIf;

	If Not CatConfigurationMetadataServer.CheckDescriptionDuplicateEnabled(Source) Then
		Return;
	EndIf;

	SourceMetadata = Source.Metadata();
	UseMultiLanguage = LocalizationReuse.UseMultiLanguage(SourceMetadata.FullName());
	AllDescription = New Array(); // Array of string
	If UseMultiLanguage Then
		AllDescription = LocalizationReuse.AllDescription();
	Else
		If CommonFunctionsClientServer.ObjectHasProperty(Source, "Description") And ValueIsFilled(Source.Description) Then
			AllDescription.Add("Description");
		EndIf;
	EndIf;
	QueryFieldsSection = New Array(); // Array of string
	QueryConditionsSection = New Array(); // Array of string
	DescriptionAttributes = New Array(); // Array of string

	Query = New Query();
	Query.Text = "SELECT
				 |	""%1"",
				 |	%2
				 |FROM
				 |	Catalog.%1 AS Cat
				 |WHERE
				 |	(%3)
				 |	AND Cat.Ref <> &Ref
				 |GROUP BY
				 |	""%1""";
	For Each Attribute In AllDescription Do
		If ValueIsFilled(Source[Attribute]) Then
			FieldLeftString = "Cat." + Attribute + " = &" + Attribute;
			FieldString = "IsNull(MAX(" + FieldLeftString + "), FALSE) AS " + Attribute;
			QueryFieldsSection.Add(FieldString);
			QueryConditionsSection.Add(FieldLeftString);
			Query.SetParameter(Attribute, Source[Attribute]);
			DescriptionAttributes.Add(Attribute);
		EndIf;
	EndDo;
	If Not DescriptionAttributes.Count() Then
		Return;
	EndIf;
	QueryFields = StrConcat(QueryFieldsSection, "," + Chars.LF + "	");
	QueryConditions = StrConcat(QueryConditionsSection, Chars.LF + "	OR ");
	Query.Text = StrTemplate(Query.Text, SourceMetadata.Name, QueryFields, QueryConditions);
	Query.SetParameter("Ref", Source.Ref);

	QueryExecution = Query.Execute();
	QuerySelection = QueryExecution.Select();
	QuerySelection.Next();
	For Each DescriptionAttribute In DescriptionAttributes Do
		If QuerySelection[DescriptionAttribute] Then
			If Not Cancel Then
				Cancel = True;
			EndIf;
			LangCode = StrReplace(DescriptionAttribute, "Description", "");
			DescriptionLanguage = ?(IsBlankString(LangCode), "", " (" + StrReplace(LangCode, "_", "") + ")");
			CommonFunctionsClientServer.ShowUsersMessage(StrTemplate(R().Error_089, DescriptionLanguage,
				Source[DescriptionAttribute]));
		EndIf;
	EndDo;
EndProcedure

#EndRegion

#Region Declaration

// Custom search filter.
//
// Returns:
//  Structure - Custom search filter:
// * FieldName - String
// * Value - Undefined
// * ComparisonType - ComparisonType -
// * DataCompositionComparisonType - Undefined
Function NewCustomSearchFilter() Export
	Structure = New Structure;
	Structure.Insert("FieldName", "");
	Structure.Insert("Value", Undefined);
	Structure.Insert("ComparisonType", ComparisonType.Equal);
	Structure.Insert("DataCompositionComparisonType", Undefined);
	Return Structure;
EndFunction

#EndRegion
