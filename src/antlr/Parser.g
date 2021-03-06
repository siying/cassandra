/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

parser grammar Parser;

options {
    language = Java;
}

@members {
    private final List<ErrorListener> listeners = new ArrayList<ErrorListener>();
    protected final List<ColumnIdentifier> bindVariables = new ArrayList<ColumnIdentifier>();

    public static final Set<String> reservedTypeNames = new HashSet<String>()
    {{
        add("byte");
        add("complex");
        add("enum");
        add("date");
        add("interval");
        add("macaddr");
        add("bitstring");
    }};

    public AbstractMarker.Raw newBindVariables(ColumnIdentifier name)
    {
        AbstractMarker.Raw marker = new AbstractMarker.Raw(bindVariables.size());
        bindVariables.add(name);
        return marker;
    }

    public AbstractMarker.INRaw newINBindVariables(ColumnIdentifier name)
    {
        AbstractMarker.INRaw marker = new AbstractMarker.INRaw(bindVariables.size());
        bindVariables.add(name);
        return marker;
    }

    public Tuples.Raw newTupleBindVariables(ColumnIdentifier name)
    {
        Tuples.Raw marker = new Tuples.Raw(bindVariables.size());
        bindVariables.add(name);
        return marker;
    }

    public Tuples.INRaw newTupleINBindVariables(ColumnIdentifier name)
    {
        Tuples.INRaw marker = new Tuples.INRaw(bindVariables.size());
        bindVariables.add(name);
        return marker;
    }

    public Json.Marker newJsonBindVariables(ColumnIdentifier name)
    {
        Json.Marker marker = new Json.Marker(bindVariables.size());
        bindVariables.add(name);
        return marker;
    }

    public void addErrorListener(ErrorListener listener)
    {
        this.listeners.add(listener);
    }

    public void removeErrorListener(ErrorListener listener)
    {
        this.listeners.remove(listener);
    }

    public void displayRecognitionError(String[] tokenNames, RecognitionException e)
    {
        for (int i = 0, m = listeners.size(); i < m; i++)
            listeners.get(i).syntaxError(this, tokenNames, e);
    }

    protected void addRecognitionError(String msg)
    {
        for (int i = 0, m = listeners.size(); i < m; i++)
            listeners.get(i).syntaxError(this, msg);
    }

    public Map<String, String> convertPropertyMap(Maps.Literal map)
    {
        if (map == null || map.entries == null || map.entries.isEmpty())
            return Collections.<String, String>emptyMap();

        Map<String, String> res = new HashMap<String, String>(map.entries.size());

        for (Pair<Term.Raw, Term.Raw> entry : map.entries)
        {
            // Because the parser tries to be smart and recover on error (to
            // allow displaying more than one error I suppose), we have null
            // entries in there. Just skip those, a proper error will be thrown in the end.
            if (entry.left == null || entry.right == null)
                break;

            if (!(entry.left instanceof Constants.Literal))
            {
                String msg = "Invalid property name: " + entry.left;
                if (entry.left instanceof AbstractMarker.Raw)
                    msg += " (bind variables are not supported in DDL queries)";
                addRecognitionError(msg);
                break;
            }
            if (!(entry.right instanceof Constants.Literal))
            {
                String msg = "Invalid property value: " + entry.right + " for property: " + entry.left;
                if (entry.right instanceof AbstractMarker.Raw)
                    msg += " (bind variables are not supported in DDL queries)";
                addRecognitionError(msg);
                break;
            }

            res.put(((Constants.Literal)entry.left).getRawText(), ((Constants.Literal)entry.right).getRawText());
        }

        return res;
    }

    public void addRawUpdate(List<Pair<ColumnIdentifier.Raw, Operation.RawUpdate>> operations, ColumnIdentifier.Raw key, Operation.RawUpdate update)
    {
        for (Pair<ColumnIdentifier.Raw, Operation.RawUpdate> p : operations)
        {
            if (p.left.equals(key) && !p.right.isCompatibleWith(update))
                addRecognitionError("Multiple incompatible setting of column " + key);
        }
        operations.add(Pair.create(key, update));
    }

    public Set<Permission> filterPermissions(Set<Permission> permissions, IResource resource)
    {
        if (resource == null)
            return Collections.emptySet();
        Set<Permission> filtered = new HashSet<>(permissions);
        filtered.retainAll(resource.applicablePermissions());
        if (filtered.isEmpty())
            addRecognitionError("Resource type " + resource.getClass().getSimpleName() +
                                    " does not support any of the requested permissions");

        return filtered;
    }

    public void buildLIKERelation(WhereClause.Builder whereClause, ColumnIdentifier.Raw name, String likeValue)
    {
        Operator operator;
        int beginIndex = 0;
        int endIndex = likeValue.length() - 1;

        if (likeValue.charAt(endIndex) == '\%')
        {
            if (likeValue.charAt(beginIndex) == '\%')
            {
                operator = Operator.LIKE_CONTAINS;
                beginIndex =+ 1;
            }
            else
            {
                operator = Operator.LIKE_PREFIX;
            }
        }
        else if (likeValue.charAt(beginIndex) == '\%')
        {
            operator = Operator.LIKE_SUFFIX;
            beginIndex += 1;
            endIndex += 1;
        }
        else
        {
            operator = Operator.LIKE_MATCHES;
            endIndex += 1;
        }

        if (endIndex == 0 || beginIndex == endIndex)
        {
            addRecognitionError("LIKE value can't be empty.");
            return;
        }

        String value = likeValue.substring(beginIndex, endIndex);
        whereClause.add(new SingleColumnRelation(name, operator, Constants.Literal.string(value)));
    }
}

/** STATEMENTS **/

cqlStatement returns [ParsedStatement stmt]
    @after{ if (stmt != null) stmt.setBoundVariables(bindVariables); }
    : st1= selectStatement                 { $stmt = st1; }
    | st2= insertStatement                 { $stmt = st2; }
    | st3= updateStatement                 { $stmt = st3; }
    | st4= batchStatement                  { $stmt = st4; }
    | st5= deleteStatement                 { $stmt = st5; }
    | st6= useStatement                    { $stmt = st6; }
    | st7= truncateStatement               { $stmt = st7; }
    | st8= createKeyspaceStatement         { $stmt = st8; }
    | st9= createTableStatement            { $stmt = st9; }
    | st10=createIndexStatement            { $stmt = st10; }
    | st11=dropKeyspaceStatement           { $stmt = st11; }
    | st12=dropTableStatement              { $stmt = st12; }
    | st13=dropIndexStatement              { $stmt = st13; }
    | st14=alterTableStatement             { $stmt = st14; }
    | st15=alterKeyspaceStatement          { $stmt = st15; }
    | st16=grantPermissionsStatement       { $stmt = st16; }
    | st17=revokePermissionsStatement      { $stmt = st17; }
    | st18=listPermissionsStatement        { $stmt = st18; }
    | st19=createUserStatement             { $stmt = st19; }
    | st20=alterUserStatement              { $stmt = st20; }
    | st21=dropUserStatement               { $stmt = st21; }
    | st22=listUsersStatement              { $stmt = st22; }
    | st23=createTriggerStatement          { $stmt = st23; }
    | st24=dropTriggerStatement            { $stmt = st24; }
    | st25=createTypeStatement             { $stmt = st25; }
    | st26=alterTypeStatement              { $stmt = st26; }
    | st27=dropTypeStatement               { $stmt = st27; }
    | st28=createFunctionStatement         { $stmt = st28; }
    | st29=dropFunctionStatement           { $stmt = st29; }
    | st30=createAggregateStatement        { $stmt = st30; }
    | st31=dropAggregateStatement          { $stmt = st31; }
    | st32=createRoleStatement             { $stmt = st32; }
    | st33=alterRoleStatement              { $stmt = st33; }
    | st34=dropRoleStatement               { $stmt = st34; }
    | st35=listRolesStatement              { $stmt = st35; }
    | st36=grantRoleStatement              { $stmt = st36; }
    | st37=revokeRoleStatement             { $stmt = st37; }
    | st38=createMaterializedViewStatement { $stmt = st38; }
    | st39=dropMaterializedViewStatement   { $stmt = st39; }
    | st40=alterMaterializedViewStatement  { $stmt = st40; }
    ;

/*
 * USE <KEYSPACE>;
 */
useStatement returns [UseStatement stmt]
    : K_USE ks=keyspaceName { $stmt = new UseStatement(ks); }
    ;

/**
 * SELECT <expression>
 * FROM <CF>
 * WHERE KEY = "key1" AND COL > 1 AND COL < 100
 * LIMIT <NUMBER>;
 */
selectStatement returns [SelectStatement.RawStatement expr]
    @init {
        boolean isDistinct = false;
        Term.Raw limit = null;
        Map<ColumnIdentifier.Raw, Boolean> orderings = new LinkedHashMap<ColumnIdentifier.Raw, Boolean>();
        boolean allowFiltering = false;
        boolean isJson = false;
    }
    : K_SELECT
      ( K_JSON { isJson = true; } )?
      ( ( K_DISTINCT { isDistinct = true; } )? sclause=selectClause )
      K_FROM cf=columnFamilyName
      ( K_WHERE wclause=whereClause )?
      ( K_ORDER K_BY orderByClause[orderings] ( ',' orderByClause[orderings] )* )?
      ( K_LIMIT rows=intValue { limit = rows; } )?
      ( K_ALLOW K_FILTERING  { allowFiltering = true; } )?
      {
          SelectStatement.Parameters params = new SelectStatement.Parameters(orderings,
                                                                             isDistinct,
                                                                             allowFiltering,
                                                                             isJson);
          WhereClause where = wclause == null ? WhereClause.empty() : wclause.build();
          $expr = new SelectStatement.RawStatement(cf, params, sclause, where, limit);
      }
    ;

selectClause returns [List<RawSelector> expr]
    : t1=selector { $expr = new ArrayList<RawSelector>(); $expr.add(t1); } (',' tN=selector { $expr.add(tN); })*
    | '\*' { $expr = Collections.<RawSelector>emptyList();}
    ;

selector returns [RawSelector s]
    @init{ ColumnIdentifier alias = null; }
    : us=unaliasedSelector (K_AS c=noncol_ident { alias = c; })? { $s = new RawSelector(us, alias); }
    ;

unaliasedSelector returns [Selectable.Raw s]
    @init { Selectable.Raw tmp = null; }
    :  ( c=cident                                  { tmp = c; }
       | K_COUNT '(' countArgument ')'             { tmp = Selectable.WithFunction.Raw.newCountRowsFunction();}
       | K_WRITETIME '(' c=cident ')'              { tmp = new Selectable.WritetimeOrTTL.Raw(c, true); }
       | K_TTL       '(' c=cident ')'              { tmp = new Selectable.WritetimeOrTTL.Raw(c, false); }
       | K_CAST      '(' sn=unaliasedSelector K_AS t=native_type ')' {tmp = new Selectable.WithCast.Raw(sn, t);}
       | f=functionName args=selectionFunctionArgs { tmp = new Selectable.WithFunction.Raw(f, args); }
       ) ( '.' fi=cident { tmp = new Selectable.WithFieldSelection.Raw(tmp, fi); } )* { $s = tmp; }
    ;

selectionFunctionArgs returns [List<Selectable.Raw> a]
    : '(' ')' { $a = Collections.emptyList(); }
    | '(' s1=unaliasedSelector { List<Selectable.Raw> args = new ArrayList<Selectable.Raw>(); args.add(s1); }
          ( ',' sn=unaliasedSelector { args.add(sn); } )*
      ')' { $a = args; }
    ;

countArgument
    : '\*'
    | i=INTEGER { if (!i.getText().equals("1")) addRecognitionError("Only COUNT(1) is supported, got COUNT(" + i.getText() + ")");}
    ;

whereClause returns [WhereClause.Builder clause]
    @init{ $clause = new WhereClause.Builder(); }
    : relationOrExpression[$clause] (K_AND relationOrExpression[$clause])*
    ;

relationOrExpression [WhereClause.Builder clause]
    : relation[$clause]
    | customIndexExpression[$clause]
    ;

customIndexExpression [WhereClause.Builder clause]
    @init{IndexName name = new IndexName();}
    : 'expr(' idxName[name] ',' t=term ')' { clause.add(new CustomIndexExpression(name, t));}
    ;

orderByClause[Map<ColumnIdentifier.Raw, Boolean> orderings]
    @init{
        boolean reversed = false;
    }
    : c=cident (K_ASC | K_DESC { reversed = true; })? { orderings.put(c, reversed); }
    ;

/**
 * INSERT INTO <CF> (<column>, <column>, <column>, ...)
 * VALUES (<value>, <value>, <value>, ...)
 * USING TIMESTAMP <long>;
 *
 */
insertStatement returns [ModificationStatement.Parsed expr]
    : K_INSERT K_INTO cf=columnFamilyName
        ( st1=normalInsertStatement[cf] { $expr = st1; }
        | K_JSON st2=jsonInsertStatement[cf] { $expr = st2; })
    ;

normalInsertStatement [CFName cf] returns [UpdateStatement.ParsedInsert expr]
    @init {
        Attributes.Raw attrs = new Attributes.Raw();
        List<ColumnIdentifier.Raw> columnNames  = new ArrayList<ColumnIdentifier.Raw>();
        List<Term.Raw> values = new ArrayList<Term.Raw>();
        boolean ifNotExists = false;
    }
    : '(' c1=cident { columnNames.add(c1); }  ( ',' cn=cident { columnNames.add(cn); } )* ')'
      K_VALUES
      '(' v1=term { values.add(v1); } ( ',' vn=term { values.add(vn); } )* ')'
      ( K_IF K_NOT K_EXISTS { ifNotExists = true; } )?
      ( usingClause[attrs] )?
      {
          $expr = new UpdateStatement.ParsedInsert(cf, attrs, columnNames, values, ifNotExists);
      }
    ;

jsonInsertStatement [CFName cf] returns [UpdateStatement.ParsedInsertJson expr]
    @init {
        Attributes.Raw attrs = new Attributes.Raw();
        boolean ifNotExists = false;
    }
    : val=jsonValue
      ( K_IF K_NOT K_EXISTS { ifNotExists = true; } )?
      ( usingClause[attrs] )?
      {
          $expr = new UpdateStatement.ParsedInsertJson(cf, attrs, val, ifNotExists);
      }
    ;

jsonValue returns [Json.Raw value]
    :
    | s=STRING_LITERAL { $value = new Json.Literal($s.text); }
    | ':' id=noncol_ident     { $value = newJsonBindVariables(id); }
    | QMARK            { $value = newJsonBindVariables(null); }
    ;

usingClause[Attributes.Raw attrs]
    : K_USING usingClauseObjective[attrs] ( K_AND usingClauseObjective[attrs] )*
    ;

usingClauseObjective[Attributes.Raw attrs]
    : K_TIMESTAMP ts=intValue { attrs.timestamp = ts; }
    | K_TTL t=intValue { attrs.timeToLive = t; }
    ;

/**
 * UPDATE <CF>
 * USING TIMESTAMP <long>
 * SET name1 = value1, name2 = value2
 * WHERE key = value;
 * [IF (EXISTS | name = value, ...)];
 */
updateStatement returns [UpdateStatement.ParsedUpdate expr]
    @init {
        Attributes.Raw attrs = new Attributes.Raw();
        List<Pair<ColumnIdentifier.Raw, Operation.RawUpdate>> operations = new ArrayList<Pair<ColumnIdentifier.Raw, Operation.RawUpdate>>();
        boolean ifExists = false;
    }
    : K_UPDATE cf=columnFamilyName
      ( usingClause[attrs] )?
      K_SET columnOperation[operations] (',' columnOperation[operations])*
      K_WHERE wclause=whereClause
      ( K_IF ( K_EXISTS { ifExists = true; } | conditions=updateConditions ))?
      {
          return new UpdateStatement.ParsedUpdate(cf,
                                                  attrs,
                                                  operations,
                                                  wclause.build(),
                                                  conditions == null ? Collections.<Pair<ColumnIdentifier.Raw, ColumnCondition.Raw>>emptyList() : conditions,
                                                  ifExists);
     }
    ;

updateConditions returns [List<Pair<ColumnIdentifier.Raw, ColumnCondition.Raw>> conditions]
    @init { conditions = new ArrayList<Pair<ColumnIdentifier.Raw, ColumnCondition.Raw>>(); }
    : columnCondition[conditions] ( K_AND columnCondition[conditions] )*
    ;


/**
 * DELETE name1, name2
 * FROM <CF>
 * USING TIMESTAMP <long>
 * WHERE KEY = keyname
   [IF (EXISTS | name = value, ...)];
 */
deleteStatement returns [DeleteStatement.Parsed expr]
    @init {
        Attributes.Raw attrs = new Attributes.Raw();
        List<Operation.RawDeletion> columnDeletions = Collections.emptyList();
        boolean ifExists = false;
    }
    : K_DELETE ( dels=deleteSelection { columnDeletions = dels; } )?
      K_FROM cf=columnFamilyName
      ( usingClauseDelete[attrs] )?
      K_WHERE wclause=whereClause
      ( K_IF ( K_EXISTS { ifExists = true; } | conditions=updateConditions ))?
      {
          return new DeleteStatement.Parsed(cf,
                                            attrs,
                                            columnDeletions,
                                            wclause.build(),
                                            conditions == null ? Collections.<Pair<ColumnIdentifier.Raw, ColumnCondition.Raw>>emptyList() : conditions,
                                            ifExists);
      }
    ;

deleteSelection returns [List<Operation.RawDeletion> operations]
    : { $operations = new ArrayList<Operation.RawDeletion>(); }
          t1=deleteOp { $operations.add(t1); }
          (',' tN=deleteOp { $operations.add(tN); })*
    ;

deleteOp returns [Operation.RawDeletion op]
    : c=cident                { $op = new Operation.ColumnDeletion(c); }
    | c=cident '[' t=term ']' { $op = new Operation.ElementDeletion(c, t); }
    ;

usingClauseDelete[Attributes.Raw attrs]
    : K_USING K_TIMESTAMP ts=intValue { attrs.timestamp = ts; }
    ;

/**
 * BEGIN BATCH
 *   UPDATE <CF> SET name1 = value1 WHERE KEY = keyname1;
 *   UPDATE <CF> SET name2 = value2 WHERE KEY = keyname2;
 *   UPDATE <CF> SET name3 = value3 WHERE KEY = keyname3;
 *   ...
 * APPLY BATCH
 *
 * OR
 *
 * BEGIN BATCH
 *   INSERT INTO <CF> (KEY, <name>) VALUES ('<key>', '<value>');
 *   INSERT INTO <CF> (KEY, <name>) VALUES ('<key>', '<value>');
 *   ...
 * APPLY BATCH
 *
 * OR
 *
 * BEGIN BATCH
 *   DELETE name1, name2 FROM <CF> WHERE key = <key>
 *   DELETE name3, name4 FROM <CF> WHERE key = <key>
 *   ...
 * APPLY BATCH
 */
batchStatement returns [BatchStatement.Parsed expr]
    @init {
        BatchStatement.Type type = BatchStatement.Type.LOGGED;
        List<ModificationStatement.Parsed> statements = new ArrayList<ModificationStatement.Parsed>();
        Attributes.Raw attrs = new Attributes.Raw();
    }
    : K_BEGIN
      ( K_UNLOGGED { type = BatchStatement.Type.UNLOGGED; } | K_COUNTER { type = BatchStatement.Type.COUNTER; } )?
      K_BATCH ( usingClause[attrs] )?
          ( s=batchStatementObjective ';'? { statements.add(s); } )*
      K_APPLY K_BATCH
      {
          return new BatchStatement.Parsed(type, attrs, statements);
      }
    ;

batchStatementObjective returns [ModificationStatement.Parsed statement]
    : i=insertStatement  { $statement = i; }
    | u=updateStatement  { $statement = u; }
    | d=deleteStatement  { $statement = d; }
    ;

createAggregateStatement returns [CreateAggregateStatement expr]
    @init {
        boolean orReplace = false;
        boolean ifNotExists = false;

        List<CQL3Type.Raw> argsTypes = new ArrayList<>();
    }
    : K_CREATE (K_OR K_REPLACE { orReplace = true; })?
      K_AGGREGATE
      (K_IF K_NOT K_EXISTS { ifNotExists = true; })?
      fn=functionName
      '('
        (
          v=comparatorType { argsTypes.add(v); }
          ( ',' v=comparatorType { argsTypes.add(v); } )*
        )?
      ')'
      K_SFUNC sfunc = allowedFunctionName
      K_STYPE stype = comparatorType
      (
        K_FINALFUNC ffunc = allowedFunctionName
      )?
      (
        K_INITCOND ival = term
      )?
      { $expr = new CreateAggregateStatement(fn, argsTypes, sfunc, stype, ffunc, ival, orReplace, ifNotExists); }
    ;

dropAggregateStatement returns [DropAggregateStatement expr]
    @init {
        boolean ifExists = false;
        List<CQL3Type.Raw> argsTypes = new ArrayList<>();
        boolean argsPresent = false;
    }
    : K_DROP K_AGGREGATE
      (K_IF K_EXISTS { ifExists = true; } )?
      fn=functionName
      (
        '('
          (
            v=comparatorType { argsTypes.add(v); }
            ( ',' v=comparatorType { argsTypes.add(v); } )*
          )?
        ')'
        { argsPresent = true; }
      )?
      { $expr = new DropAggregateStatement(fn, argsTypes, argsPresent, ifExists); }
    ;

createFunctionStatement returns [CreateFunctionStatement expr]
    @init {
        boolean orReplace = false;
        boolean ifNotExists = false;

        List<ColumnIdentifier> argsNames = new ArrayList<>();
        List<CQL3Type.Raw> argsTypes = new ArrayList<>();
        boolean calledOnNullInput = false;
    }
    : K_CREATE (K_OR K_REPLACE { orReplace = true; })?
      K_FUNCTION
      (K_IF K_NOT K_EXISTS { ifNotExists = true; })?
      fn=functionName
      '('
        (
          k=noncol_ident v=comparatorType { argsNames.add(k); argsTypes.add(v); }
          ( ',' k=noncol_ident v=comparatorType { argsNames.add(k); argsTypes.add(v); } )*
        )?
      ')'
      ( (K_RETURNS K_NULL) | (K_CALLED { calledOnNullInput=true; })) K_ON K_NULL K_INPUT
      K_RETURNS rt = comparatorType
      K_LANGUAGE language = IDENT
      K_AS body = STRING_LITERAL
      { $expr = new CreateFunctionStatement(fn, $language.text.toLowerCase(), $body.text,
                                            argsNames, argsTypes, rt, calledOnNullInput, orReplace, ifNotExists); }
    ;

dropFunctionStatement returns [DropFunctionStatement expr]
    @init {
        boolean ifExists = false;
        List<CQL3Type.Raw> argsTypes = new ArrayList<>();
        boolean argsPresent = false;
    }
    : K_DROP K_FUNCTION
      (K_IF K_EXISTS { ifExists = true; } )?
      fn=functionName
      (
        '('
          (
            v=comparatorType { argsTypes.add(v); }
            ( ',' v=comparatorType { argsTypes.add(v); } )*
          )?
        ')'
        { argsPresent = true; }
      )?
      { $expr = new DropFunctionStatement(fn, argsTypes, argsPresent, ifExists); }
    ;

/**
 * CREATE KEYSPACE [IF NOT EXISTS] <KEYSPACE> WITH attr1 = value1 AND attr2 = value2;
 */
createKeyspaceStatement returns [CreateKeyspaceStatement expr]
    @init {
        KeyspaceAttributes attrs = new KeyspaceAttributes();
        boolean ifNotExists = false;
    }
    : K_CREATE K_KEYSPACE (K_IF K_NOT K_EXISTS { ifNotExists = true; } )? ks=keyspaceName
      K_WITH properties[attrs] { $expr = new CreateKeyspaceStatement(ks, attrs, ifNotExists); }
    ;

/**
 * CREATE COLUMNFAMILY [IF NOT EXISTS] <CF> (
 *     <name1> <type>,
 *     <name2> <type>,
 *     <name3> <type>
 * ) WITH <property> = <value> AND ...;
 */
createTableStatement returns [CreateTableStatement.RawStatement expr]
    @init { boolean ifNotExists = false; }
    : K_CREATE K_COLUMNFAMILY (K_IF K_NOT K_EXISTS { ifNotExists = true; } )?
      cf=columnFamilyName { $expr = new CreateTableStatement.RawStatement(cf, ifNotExists); }
      cfamDefinition[expr]
    ;

cfamDefinition[CreateTableStatement.RawStatement expr]
    : '(' cfamColumns[expr] ( ',' cfamColumns[expr]? )* ')'
      ( K_WITH cfamProperty[expr.properties] ( K_AND cfamProperty[expr.properties] )*)?
    ;

cfamColumns[CreateTableStatement.RawStatement expr]
    : k=ident v=comparatorType { boolean isStatic=false; } (K_STATIC {isStatic = true;})? { $expr.addDefinition(k, v, isStatic); }
        (K_PRIMARY K_KEY { $expr.addKeyAliases(Collections.singletonList(k)); })?
    | K_PRIMARY K_KEY '(' pkDef[expr] (',' c=ident { $expr.addColumnAlias(c); } )* ')'
    ;

pkDef[CreateTableStatement.RawStatement expr]
    : k=ident { $expr.addKeyAliases(Collections.singletonList(k)); }
    | '(' { List<ColumnIdentifier> l = new ArrayList<ColumnIdentifier>(); } k1=ident { l.add(k1); } ( ',' kn=ident { l.add(kn); } )* ')' { $expr.addKeyAliases(l); }
    ;

cfamProperty[CFProperties props]
    : property[props.properties]
    | K_COMPACT K_STORAGE { $props.setCompactStorage(); }
    | K_CLUSTERING K_ORDER K_BY '(' cfamOrdering[props] (',' cfamOrdering[props])* ')'
    ;

cfamOrdering[CFProperties props]
    @init{ boolean reversed=false; }
    : k=ident (K_ASC | K_DESC { reversed=true;} ) { $props.setOrdering(k, reversed); }
    ;


/**
 * CREATE TYPE foo (
 *    <name1> <type1>,
 *    <name2> <type2>,
 *    ....
 * )
 */
createTypeStatement returns [CreateTypeStatement expr]
    @init { boolean ifNotExists = false; }
    : K_CREATE K_TYPE (K_IF K_NOT K_EXISTS { ifNotExists = true; } )?
         tn=userTypeName { $expr = new CreateTypeStatement(tn, ifNotExists); }
         '(' typeColumns[expr] ( ',' typeColumns[expr]? )* ')'
    ;

typeColumns[CreateTypeStatement expr]
    : k=noncol_ident v=comparatorType { $expr.addDefinition(k, v); }
    ;


/**
 * CREATE INDEX [IF NOT EXISTS] [indexName] ON <columnFamily> (<columnName>);
 * CREATE CUSTOM INDEX [IF NOT EXISTS] [indexName] ON <columnFamily> (<columnName>) USING <indexClass>;
 */
createIndexStatement returns [CreateIndexStatement expr]
    @init {
        IndexPropDefs props = new IndexPropDefs();
        boolean ifNotExists = false;
        IndexName name = new IndexName();
        List<IndexTarget.Raw> targets = new ArrayList<>();
    }
    : K_CREATE (K_CUSTOM { props.isCustom = true; })? K_INDEX (K_IF K_NOT K_EXISTS { ifNotExists = true; } )?
        (idxName[name])? K_ON cf=columnFamilyName '(' (indexIdent[targets] (',' indexIdent[targets])*)? ')'
        (K_USING cls=STRING_LITERAL { props.customClass = $cls.text; })?
        (K_WITH properties[props])?
      { $expr = new CreateIndexStatement(cf, name, targets, props, ifNotExists); }
    ;

indexIdent [List<IndexTarget.Raw> targets]
    : c=cident                   { $targets.add(IndexTarget.Raw.simpleIndexOn(c)); }
    | K_VALUES '(' c=cident ')'  { $targets.add(IndexTarget.Raw.valuesOf(c)); }
    | K_KEYS '(' c=cident ')'    { $targets.add(IndexTarget.Raw.keysOf(c)); }
    | K_ENTRIES '(' c=cident ')' { $targets.add(IndexTarget.Raw.keysAndValuesOf(c)); }
    | K_FULL '(' c=cident ')'    { $targets.add(IndexTarget.Raw.fullCollection(c)); }
    ;

/**
 * CREATE MATERIALIZED VIEW <viewName> AS
 *  SELECT <columns>
 *  FROM <CF>
 *  WHERE <pkColumns> IS NOT NULL
 *  PRIMARY KEY (<pkColumns>)
 *  WITH <property> = <value> AND ...;
 */
createMaterializedViewStatement returns [CreateViewStatement expr]
    @init {
        boolean ifNotExists = false;
        List<ColumnIdentifier.Raw> partitionKeys = new ArrayList<>();
        List<ColumnIdentifier.Raw> compositeKeys = new ArrayList<>();
    }
    : K_CREATE K_MATERIALIZED K_VIEW (K_IF K_NOT K_EXISTS { ifNotExists = true; })? cf=columnFamilyName K_AS
        K_SELECT sclause=selectClause K_FROM basecf=columnFamilyName
        (K_WHERE wclause=whereClause)?
        K_PRIMARY K_KEY (
        '(' '(' k1=cident { partitionKeys.add(k1); } ( ',' kn=cident { partitionKeys.add(kn); } )* ')' ( ',' c1=cident { compositeKeys.add(c1); } )* ')'
    |   '(' k1=cident { partitionKeys.add(k1); } ( ',' cn=cident { compositeKeys.add(cn); } )* ')'
        )
        {
             WhereClause where = wclause == null ? WhereClause.empty() : wclause.build();
             $expr = new CreateViewStatement(cf, basecf, sclause, where, partitionKeys, compositeKeys, ifNotExists);
        }
        ( K_WITH cfamProperty[expr.properties] ( K_AND cfamProperty[expr.properties] )*)?
    ;

/**
 * CREATE TRIGGER triggerName ON columnFamily USING 'triggerClass';
 */
createTriggerStatement returns [CreateTriggerStatement expr]
    @init {
        boolean ifNotExists = false;
    }
    : K_CREATE K_TRIGGER (K_IF K_NOT K_EXISTS { ifNotExists = true; } )? (name=cident)
        K_ON cf=columnFamilyName K_USING cls=STRING_LITERAL
      { $expr = new CreateTriggerStatement(cf, name.toString(), $cls.text, ifNotExists); }
    ;

/**
 * DROP TRIGGER [IF EXISTS] triggerName ON columnFamily;
 */
dropTriggerStatement returns [DropTriggerStatement expr]
     @init { boolean ifExists = false; }
    : K_DROP K_TRIGGER (K_IF K_EXISTS { ifExists = true; } )? (name=cident) K_ON cf=columnFamilyName
      { $expr = new DropTriggerStatement(cf, name.toString(), ifExists); }
    ;

/**
 * ALTER KEYSPACE <KS> WITH <property> = <value>;
 */
alterKeyspaceStatement returns [AlterKeyspaceStatement expr]
    @init { KeyspaceAttributes attrs = new KeyspaceAttributes(); }
    : K_ALTER K_KEYSPACE ks=keyspaceName
        K_WITH properties[attrs] { $expr = new AlterKeyspaceStatement(ks, attrs); }
    ;


/**
 * ALTER COLUMN FAMILY <CF> ALTER <column> TYPE <newtype>;
 * ALTER COLUMN FAMILY <CF> ADD <column> <newtype>; | ALTER COLUMN FAMILY <CF> ADD (<column> <newtype>,<column1> <newtype1>..... <column n> <newtype n>)
 * ALTER COLUMN FAMILY <CF> DROP <column>; | ALTER COLUMN FAMILY <CF> DROP ( <column>,<column1>.....<column n>)
 * ALTER COLUMN FAMILY <CF> WITH <property> = <value>;
 * ALTER COLUMN FAMILY <CF> RENAME <column> TO <column>;
 */
alterTableStatement returns [AlterTableStatement expr]
    @init {
        AlterTableStatement.Type type = null;
        TableAttributes attrs = new TableAttributes();
        Map<ColumnIdentifier.Raw, ColumnIdentifier.Raw> renames = new HashMap<ColumnIdentifier.Raw, ColumnIdentifier.Raw>();
        List<AlterTableStatementColumn> colNameList = new ArrayList<AlterTableStatementColumn>();
    }
    : K_ALTER K_COLUMNFAMILY cf=columnFamilyName
          ( K_ALTER id=cident  K_TYPE v=comparatorType  { type = AlterTableStatement.Type.ALTER; } { colNameList.add(new AlterTableStatementColumn(id,v)); }
          | K_ADD  (        (id=cident   v=comparatorType   b1=cfisStatic { colNameList.add(new AlterTableStatementColumn(id,v,b1)); })
                     | ('('  id1=cident  v1=comparatorType  b1=cfisStatic { colNameList.add(new AlterTableStatementColumn(id1,v1,b1)); }
                       ( ',' idn=cident  vn=comparatorType  bn=cfisStatic { colNameList.add(new AlterTableStatementColumn(idn,vn,bn)); } )* ')' ) ) { type = AlterTableStatement.Type.ADD; }
          | K_DROP (         id=cident  { colNameList.add(new AlterTableStatementColumn(id)); }
                     | ('('  id1=cident { colNameList.add(new AlterTableStatementColumn(id1)); }
                       ( ',' idn=cident { colNameList.add(new AlterTableStatementColumn(idn)); } )* ')') ) { type = AlterTableStatement.Type.DROP; }
          | K_WITH  properties[attrs]                 { type = AlterTableStatement.Type.OPTS; }
          | K_RENAME                                  { type = AlterTableStatement.Type.RENAME; }
               id1=cident K_TO toId1=cident { renames.put(id1, toId1); }
               ( K_AND idn=cident K_TO toIdn=cident { renames.put(idn, toIdn); } )*
          )
    {
        $expr = new AlterTableStatement(cf, type, colNameList, attrs, renames);
    }
    ;

cfisStatic returns [boolean isStaticColumn]
    @init{
        boolean isStatic = false;
    }
    : (K_STATIC { isStatic=true; })? { $isStaticColumn = isStatic;
    }
    ;

alterMaterializedViewStatement returns [AlterViewStatement expr]
    @init {
        TableAttributes attrs = new TableAttributes();
    }
    : K_ALTER K_MATERIALIZED K_VIEW name=columnFamilyName
          K_WITH properties[attrs]
    {
        $expr = new AlterViewStatement(name, attrs);
    }
    ;


/**
 * ALTER TYPE <name> ALTER <field> TYPE <newtype>;
 * ALTER TYPE <name> ADD <field> <newtype>;
 * ALTER TYPE <name> RENAME <field> TO <newtype> AND ...;
 */
alterTypeStatement returns [AlterTypeStatement expr]
    : K_ALTER K_TYPE name=userTypeName
          ( K_ALTER f=noncol_ident K_TYPE v=comparatorType { $expr = AlterTypeStatement.alter(name, f, v); }
          | K_ADD   f=noncol_ident v=comparatorType        { $expr = AlterTypeStatement.addition(name, f, v); }
          | K_RENAME
               { Map<ColumnIdentifier, ColumnIdentifier> renames = new HashMap<ColumnIdentifier, ColumnIdentifier>(); }
                 id1=noncol_ident K_TO toId1=noncol_ident { renames.put(id1, toId1); }
                 ( K_AND idn=noncol_ident K_TO toIdn=noncol_ident { renames.put(idn, toIdn); } )*
               { $expr = AlterTypeStatement.renames(name, renames); }
          )
    ;


/**
 * DROP KEYSPACE [IF EXISTS] <KSP>;
 */
dropKeyspaceStatement returns [DropKeyspaceStatement ksp]
    @init { boolean ifExists = false; }
    : K_DROP K_KEYSPACE (K_IF K_EXISTS { ifExists = true; } )? ks=keyspaceName { $ksp = new DropKeyspaceStatement(ks, ifExists); }
    ;

/**
 * DROP COLUMNFAMILY [IF EXISTS] <CF>;
 */
dropTableStatement returns [DropTableStatement stmt]
    @init { boolean ifExists = false; }
    : K_DROP K_COLUMNFAMILY (K_IF K_EXISTS { ifExists = true; } )? cf=columnFamilyName { $stmt = new DropTableStatement(cf, ifExists); }
    ;

/**
 * DROP TYPE <name>;
 */
dropTypeStatement returns [DropTypeStatement stmt]
    @init { boolean ifExists = false; }
    : K_DROP K_TYPE (K_IF K_EXISTS { ifExists = true; } )? name=userTypeName { $stmt = new DropTypeStatement(name, ifExists); }
    ;

/**
 * DROP INDEX [IF EXISTS] <INDEX_NAME>
 */
dropIndexStatement returns [DropIndexStatement expr]
    @init { boolean ifExists = false; }
    : K_DROP K_INDEX (K_IF K_EXISTS { ifExists = true; } )? index=indexName
      { $expr = new DropIndexStatement(index, ifExists); }
    ;

/**
 * DROP MATERIALIZED VIEW [IF EXISTS] <view_name>
 */
dropMaterializedViewStatement returns [DropViewStatement expr]
    @init { boolean ifExists = false; }
    : K_DROP K_MATERIALIZED K_VIEW (K_IF K_EXISTS { ifExists = true; } )? cf=columnFamilyName
      { $expr = new DropViewStatement(cf, ifExists); }
    ;

/**
  * TRUNCATE <CF>;
  */
truncateStatement returns [TruncateStatement stmt]
    : K_TRUNCATE (K_COLUMNFAMILY)? cf=columnFamilyName { $stmt = new TruncateStatement(cf); }
    ;

/**
 * GRANT <permission> ON <resource> TO <rolename>
 */
grantPermissionsStatement returns [GrantPermissionsStatement stmt]
    : K_GRANT
          permissionOrAll
      K_ON
          resource
      K_TO
          grantee=userOrRoleName
      { $stmt = new GrantPermissionsStatement(filterPermissions($permissionOrAll.perms, $resource.res), $resource.res, grantee); }
    ;

/**
 * REVOKE <permission> ON <resource> FROM <rolename>
 */
revokePermissionsStatement returns [RevokePermissionsStatement stmt]
    : K_REVOKE
          permissionOrAll
      K_ON
          resource
      K_FROM
          revokee=userOrRoleName
      { $stmt = new RevokePermissionsStatement(filterPermissions($permissionOrAll.perms, $resource.res), $resource.res, revokee); }
    ;

/**
 * GRANT ROLE <rolename> TO <grantee>
 */
grantRoleStatement returns [GrantRoleStatement stmt]
    : K_GRANT
          role=userOrRoleName
      K_TO
          grantee=userOrRoleName
      { $stmt = new GrantRoleStatement(role, grantee); }
    ;

/**
 * REVOKE ROLE <rolename> FROM <revokee>
 */
revokeRoleStatement returns [RevokeRoleStatement stmt]
    : K_REVOKE
          role=userOrRoleName
      K_FROM
          revokee=userOrRoleName
      { $stmt = new RevokeRoleStatement(role, revokee); }
    ;

listPermissionsStatement returns [ListPermissionsStatement stmt]
    @init {
        IResource resource = null;
        boolean recursive = true;
        RoleName grantee = new RoleName();
    }
    : K_LIST
          permissionOrAll
      ( K_ON resource { resource = $resource.res; } )?
      ( K_OF roleName[grantee] )?
      ( K_NORECURSIVE { recursive = false; } )?
      { $stmt = new ListPermissionsStatement($permissionOrAll.perms, resource, grantee, recursive); }
    ;

permission returns [Permission perm]
    : p=(K_CREATE | K_ALTER | K_DROP | K_SELECT | K_MODIFY | K_AUTHORIZE | K_DESCRIBE | K_EXECUTE)
    { $perm = Permission.valueOf($p.text.toUpperCase()); }
    ;

permissionOrAll returns [Set<Permission> perms]
    : K_ALL ( K_PERMISSIONS )?       { $perms = Permission.ALL; }
    | p=permission ( K_PERMISSION )? { $perms = EnumSet.of($p.perm); }
    ;

resource returns [IResource res]
    : d=dataResource { $res = $d.res; }
    | r=roleResource { $res = $r.res; }
    | f=functionResource { $res = $f.res; }
    ;

dataResource returns [DataResource res]
    : K_ALL K_KEYSPACES { $res = DataResource.root(); }
    | K_KEYSPACE ks = keyspaceName { $res = DataResource.keyspace($ks.id); }
    | ( K_COLUMNFAMILY )? cf = columnFamilyName
      { $res = DataResource.table($cf.name.getKeyspace(), $cf.name.getColumnFamily()); }
    ;

roleResource returns [RoleResource res]
    : K_ALL K_ROLES { $res = RoleResource.root(); }
    | K_ROLE role = userOrRoleName { $res = RoleResource.role($role.name.getName()); }
    ;

functionResource returns [FunctionResource res]
    @init {
        List<CQL3Type.Raw> argsTypes = new ArrayList<>();
    }
    : K_ALL K_FUNCTIONS { $res = FunctionResource.root(); }
    | K_ALL K_FUNCTIONS K_IN K_KEYSPACE ks = keyspaceName { $res = FunctionResource.keyspace($ks.id); }
    // Arg types are mandatory for DCL statements on Functions
    | K_FUNCTION fn=functionName
      (
        '('
          (
            v=comparatorType { argsTypes.add(v); }
            ( ',' v=comparatorType { argsTypes.add(v); } )*
          )?
        ')'
      )
      { $res = FunctionResource.functionFromCql($fn.s.keyspace, $fn.s.name, argsTypes); }
    ;

/**
 * CREATE USER [IF NOT EXISTS] <username> [WITH PASSWORD <password>] [SUPERUSER|NOSUPERUSER]
 */
createUserStatement returns [CreateRoleStatement stmt]
    @init {
        RoleOptions opts = new RoleOptions();
        opts.setOption(IRoleManager.Option.LOGIN, true);
        boolean superuser = false;
        boolean ifNotExists = false;
        RoleName name = new RoleName();
    }
    : K_CREATE K_USER (K_IF K_NOT K_EXISTS { ifNotExists = true; })? u=username { name.setName($u.text, true); }
      ( K_WITH userPassword[opts] )?
      ( K_SUPERUSER { superuser = true; } | K_NOSUPERUSER { superuser = false; } )?
      { opts.setOption(IRoleManager.Option.SUPERUSER, superuser);
        $stmt = new CreateRoleStatement(name, opts, ifNotExists); }
    ;

/**
 * ALTER USER <username> [WITH PASSWORD <password>] [SUPERUSER|NOSUPERUSER]
 */
alterUserStatement returns [AlterRoleStatement stmt]
    @init {
        RoleOptions opts = new RoleOptions();
        RoleName name = new RoleName();
    }
    : K_ALTER K_USER u=username { name.setName($u.text, false); }
      ( K_WITH userPassword[opts] )?
      ( K_SUPERUSER { opts.setOption(IRoleManager.Option.SUPERUSER, true); }
        | K_NOSUPERUSER { opts.setOption(IRoleManager.Option.SUPERUSER, false); } ) ?
      {  $stmt = new AlterRoleStatement(name, opts); }
    ;

/**
 * DROP USER [IF EXISTS] <username>
 */
dropUserStatement returns [DropRoleStatement stmt]
    @init {
        boolean ifExists = false;
        RoleName name = new RoleName();
    }
    : K_DROP K_USER (K_IF K_EXISTS { ifExists = true; })? u=username { name.setName($u.text, false); $stmt = new DropRoleStatement(name, ifExists); }
    ;

/**
 * LIST USERS
 */
listUsersStatement returns [ListRolesStatement stmt]
    : K_LIST K_USERS { $stmt = new ListUsersStatement(); }
    ;

/**
 * CREATE ROLE [IF NOT EXISTS] <rolename> [ [WITH] option [ [AND] option ]* ]
 *
 * where option can be:
 *  PASSWORD = '<password>'
 *  SUPERUSER = (true|false)
 *  LOGIN = (true|false)
 *  OPTIONS = { 'k1':'v1', 'k2':'v2'}
 */
createRoleStatement returns [CreateRoleStatement stmt]
    @init {
        RoleOptions opts = new RoleOptions();
        boolean ifNotExists = false;
    }
    : K_CREATE K_ROLE (K_IF K_NOT K_EXISTS { ifNotExists = true; })? name=userOrRoleName
      ( K_WITH roleOptions[opts] )?
      {
        // set defaults if they weren't explictly supplied
        if (!opts.getLogin().isPresent())
        {
            opts.setOption(IRoleManager.Option.LOGIN, false);
        }
        if (!opts.getSuperuser().isPresent())
        {
            opts.setOption(IRoleManager.Option.SUPERUSER, false);
        }
        $stmt = new CreateRoleStatement(name, opts, ifNotExists);
      }
    ;

/**
 * ALTER ROLE <rolename> [ [WITH] option [ [AND] option ]* ]
 *
 * where option can be:
 *  PASSWORD = '<password>'
 *  SUPERUSER = (true|false)
 *  LOGIN = (true|false)
 *  OPTIONS = { 'k1':'v1', 'k2':'v2'}
 */
alterRoleStatement returns [AlterRoleStatement stmt]
    @init {
        RoleOptions opts = new RoleOptions();
    }
    : K_ALTER K_ROLE name=userOrRoleName
      ( K_WITH roleOptions[opts] )?
      {  $stmt = new AlterRoleStatement(name, opts); }
    ;

/**
 * DROP ROLE [IF EXISTS] <rolename>
 */
dropRoleStatement returns [DropRoleStatement stmt]
    @init {
        boolean ifExists = false;
    }
    : K_DROP K_ROLE (K_IF K_EXISTS { ifExists = true; })? name=userOrRoleName
      { $stmt = new DropRoleStatement(name, ifExists); }
    ;

/**
 * LIST ROLES [OF <rolename>] [NORECURSIVE]
 */
listRolesStatement returns [ListRolesStatement stmt]
    @init {
        boolean recursive = true;
        RoleName grantee = new RoleName();
    }
    : K_LIST K_ROLES
      ( K_OF roleName[grantee])?
      ( K_NORECURSIVE { recursive = false; } )?
      { $stmt = new ListRolesStatement(grantee, recursive); }
    ;

roleOptions[RoleOptions opts]
    : roleOption[opts] (K_AND roleOption[opts])*
    ;

roleOption[RoleOptions opts]
    :  K_PASSWORD '=' v=STRING_LITERAL { opts.setOption(IRoleManager.Option.PASSWORD, $v.text); }
    |  K_OPTIONS '=' m=mapLiteral { opts.setOption(IRoleManager.Option.OPTIONS, convertPropertyMap(m)); }
    |  K_SUPERUSER '=' b=BOOLEAN { opts.setOption(IRoleManager.Option.SUPERUSER, Boolean.valueOf($b.text)); }
    |  K_LOGIN '=' b=BOOLEAN { opts.setOption(IRoleManager.Option.LOGIN, Boolean.valueOf($b.text)); }
    ;

// for backwards compatibility in CREATE/ALTER USER, this has no '='
userPassword[RoleOptions opts]
    :  K_PASSWORD v=STRING_LITERAL { opts.setOption(IRoleManager.Option.PASSWORD, $v.text); }
    ;

/** DEFINITIONS **/

// Column Identifiers.  These need to be treated differently from other
// identifiers because the underlying comparator is not necessarily text. See
// CASSANDRA-8178 for details.
cident returns [ColumnIdentifier.Raw id]
    : t=IDENT              { $id = new ColumnIdentifier.Literal($t.text, false); }
    | t=QUOTED_NAME        { $id = new ColumnIdentifier.Literal($t.text, true); }
    | k=unreserved_keyword { $id = new ColumnIdentifier.Literal(k, false); }
    ;

// Column identifiers where the comparator is known to be text
ident returns [ColumnIdentifier id]
    : t=IDENT              { $id = ColumnIdentifier.getInterned($t.text, false); }
    | t=QUOTED_NAME        { $id = ColumnIdentifier.getInterned($t.text, true); }
    | k=unreserved_keyword { $id = ColumnIdentifier.getInterned(k, false); }
    ;

// Identifiers that do not refer to columns
noncol_ident returns [ColumnIdentifier id]
    : t=IDENT              { $id = new ColumnIdentifier($t.text, false); }
    | t=QUOTED_NAME        { $id = new ColumnIdentifier($t.text, true); }
    | k=unreserved_keyword { $id = new ColumnIdentifier(k, false); }
    ;

// Keyspace & Column family names
keyspaceName returns [String id]
    @init { CFName name = new CFName(); }
    : ksName[name] { $id = name.getKeyspace(); }
    ;

indexName returns [IndexName name]
    @init { $name = new IndexName(); }
    : (ksName[name] '.')? idxName[name]
    ;

columnFamilyName returns [CFName name]
    @init { $name = new CFName(); }
    : (ksName[name] '.')? cfName[name]
    ;

userTypeName returns [UTName name]
    : (ks=noncol_ident '.')? ut=non_type_ident { return new UTName(ks, ut); }
    ;

userOrRoleName returns [RoleName name]
    @init { $name = new RoleName(); }
    : roleName[name] {return $name;}
    ;

ksName[KeyspaceElementName name]
    : t=IDENT              { $name.setKeyspace($t.text, false);}
    | t=QUOTED_NAME        { $name.setKeyspace($t.text, true);}
    | k=unreserved_keyword { $name.setKeyspace(k, false);}
    | QMARK {addRecognitionError("Bind variables cannot be used for keyspace names");}
    ;

cfName[CFName name]
    : t=IDENT              { $name.setColumnFamily($t.text, false); }
    | t=QUOTED_NAME        { $name.setColumnFamily($t.text, true); }
    | k=unreserved_keyword { $name.setColumnFamily(k, false); }
    | QMARK {addRecognitionError("Bind variables cannot be used for table names");}
    ;

idxName[IndexName name]
    : t=IDENT              { $name.setIndex($t.text, false); }
    | t=QUOTED_NAME        { $name.setIndex($t.text, true);}
    | k=unreserved_keyword { $name.setIndex(k, false); }
    | QMARK {addRecognitionError("Bind variables cannot be used for index names");}
    ;

roleName[RoleName name]
    : t=IDENT              { $name.setName($t.text, false); }
    | s=STRING_LITERAL     { $name.setName($s.text, true); }
    | t=QUOTED_NAME        { $name.setName($t.text, true); }
    | k=unreserved_keyword { $name.setName(k, false); }
    | QMARK {addRecognitionError("Bind variables cannot be used for role names");}
    ;

constant returns [Constants.Literal constant]
    : t=STRING_LITERAL { $constant = Constants.Literal.string($t.text); }
    | t=INTEGER        { $constant = Constants.Literal.integer($t.text); }
    | t=FLOAT          { $constant = Constants.Literal.floatingPoint($t.text); }
    | t=BOOLEAN        { $constant = Constants.Literal.bool($t.text); }
    | t=UUID           { $constant = Constants.Literal.uuid($t.text); }
    | t=HEXNUMBER      { $constant = Constants.Literal.hex($t.text); }
    | { String sign=""; } ('-' {sign = "-"; } )? t=(K_NAN | K_INFINITY) { $constant = Constants.Literal.floatingPoint(sign + $t.text); }
    ;

mapLiteral returns [Maps.Literal map]
    : '{' { List<Pair<Term.Raw, Term.Raw>> m = new ArrayList<Pair<Term.Raw, Term.Raw>>(); }
          ( k1=term ':' v1=term { m.add(Pair.create(k1, v1)); } ( ',' kn=term ':' vn=term { m.add(Pair.create(kn, vn)); } )* )?
      '}' { $map = new Maps.Literal(m); }
    ;

setOrMapLiteral[Term.Raw t] returns [Term.Raw value]
    : ':' v=term { List<Pair<Term.Raw, Term.Raw>> m = new ArrayList<Pair<Term.Raw, Term.Raw>>(); m.add(Pair.create(t, v)); }
          ( ',' kn=term ':' vn=term { m.add(Pair.create(kn, vn)); } )*
      { $value = new Maps.Literal(m); }
    | { List<Term.Raw> s = new ArrayList<Term.Raw>(); s.add(t); }
          ( ',' tn=term { s.add(tn); } )*
      { $value = new Sets.Literal(s); }
    ;

collectionLiteral returns [Term.Raw value]
    : '[' { List<Term.Raw> l = new ArrayList<Term.Raw>(); }
          ( t1=term { l.add(t1); } ( ',' tn=term { l.add(tn); } )* )?
      ']' { $value = new Lists.Literal(l); }
    | '{' t=term v=setOrMapLiteral[t] { $value = v; } '}'
    // Note that we have an ambiguity between maps and set for "{}". So we force it to a set literal,
    // and deal with it later based on the type of the column (SetLiteral.java).
    | '{' '}' { $value = new Sets.Literal(Collections.<Term.Raw>emptyList()); }
    ;

usertypeLiteral returns [UserTypes.Literal ut]
    @init{ Map<ColumnIdentifier, Term.Raw> m = new HashMap<ColumnIdentifier, Term.Raw>(); }
    @after{ $ut = new UserTypes.Literal(m); }
    // We don't allow empty literals because that conflicts with sets/maps and is currently useless since we don't allow empty user types
    : '{' k1=noncol_ident ':' v1=term { m.put(k1, v1); } ( ',' kn=noncol_ident ':' vn=term { m.put(kn, vn); } )* '}'
    ;

tupleLiteral returns [Tuples.Literal tt]
    @init{ List<Term.Raw> l = new ArrayList<Term.Raw>(); }
    @after{ $tt = new Tuples.Literal(l); }
    : '(' t1=term { l.add(t1); } ( ',' tn=term { l.add(tn); } )* ')'
    ;

value returns [Term.Raw value]
    : c=constant           { $value = c; }
    | l=collectionLiteral  { $value = l; }
    | u=usertypeLiteral    { $value = u; }
    | t=tupleLiteral       { $value = t; }
    | K_NULL               { $value = Constants.NULL_LITERAL; }
    | ':' id=noncol_ident  { $value = newBindVariables(id); }
    | QMARK                { $value = newBindVariables(null); }
    ;

intValue returns [Term.Raw value]
    :
    | t=INTEGER     { $value = Constants.Literal.integer($t.text); }
    | ':' id=noncol_ident  { $value = newBindVariables(id); }
    | QMARK         { $value = newBindVariables(null); }
    ;

functionName returns [FunctionName s]
    : (ks=keyspaceName '.')? f=allowedFunctionName   { $s = new FunctionName(ks, f); }
    ;

allowedFunctionName returns [String s]
    : f=IDENT                       { $s = $f.text.toLowerCase(); }
    | f=QUOTED_NAME                 { $s = $f.text; }
    | u=unreserved_function_keyword { $s = u; }
    | K_TOKEN                       { $s = "token"; }
    | K_COUNT                       { $s = "count"; }
    ;

function returns [Term.Raw t]
    : f=functionName '(' ')'                   { $t = new FunctionCall.Raw(f, Collections.<Term.Raw>emptyList()); }
    | f=functionName '(' args=functionArgs ')' { $t = new FunctionCall.Raw(f, args); }
    ;

functionArgs returns [List<Term.Raw> args]
    @init{ $args = new ArrayList<Term.Raw>(); }
    : t1=term {args.add(t1); } ( ',' tn=term { args.add(tn); } )*
    ;

term returns [Term.Raw term]
    : v=value                          { $term = v; }
    | f=function                       { $term = f; }
    | '(' c=comparatorType ')' t=term  { $term = new TypeCast(c, t); }
    ;

columnOperation[List<Pair<ColumnIdentifier.Raw, Operation.RawUpdate>> operations]
    : key=cident columnOperationDifferentiator[operations, key]
    ;

columnOperationDifferentiator[List<Pair<ColumnIdentifier.Raw, Operation.RawUpdate>> operations, ColumnIdentifier.Raw key]
    : '=' normalColumnOperation[operations, key]
    | '[' k=term ']' specializedColumnOperation[operations, key, k]
    ;

normalColumnOperation[List<Pair<ColumnIdentifier.Raw, Operation.RawUpdate>> operations, ColumnIdentifier.Raw key]
    : t=term ('+' c=cident )?
      {
          if (c == null)
          {
              addRawUpdate(operations, key, new Operation.SetValue(t));
          }
          else
          {
              if (!key.equals(c))
                  addRecognitionError("Only expressions of the form X = <value> + X are supported.");
              addRawUpdate(operations, key, new Operation.Prepend(t));
          }
      }
    | c=cident sig=('+' | '-') t=term
      {
          if (!key.equals(c))
              addRecognitionError("Only expressions of the form X = X " + $sig.text + "<value> are supported.");
          addRawUpdate(operations, key, $sig.text.equals("+") ? new Operation.Addition(t) : new Operation.Substraction(t));
      }
    | c=cident i=INTEGER
      {
          // Note that this production *is* necessary because X = X - 3 will in fact be lexed as [ X, '=', X, INTEGER].
          if (!key.equals(c))
              // We don't yet allow a '+' in front of an integer, but we could in the future really, so let's be future-proof in our error message
              addRecognitionError("Only expressions of the form X = X " + ($i.text.charAt(0) == '-' ? '-' : '+') + " <value> are supported.");
          addRawUpdate(operations, key, new Operation.Addition(Constants.Literal.integer($i.text)));
      }
    ;

specializedColumnOperation[List<Pair<ColumnIdentifier.Raw, Operation.RawUpdate>> operations, ColumnIdentifier.Raw key, Term.Raw k]
    : '=' t=term
      {
          addRawUpdate(operations, key, new Operation.SetElement(k, t));
      }
    ;

columnCondition[List<Pair<ColumnIdentifier.Raw, ColumnCondition.Raw>> conditions]
    // Note: we'll reject duplicates later
    : key=cident
        ( op=relationType t=term { conditions.add(Pair.create(key, ColumnCondition.Raw.simpleCondition(t, op))); }
        | K_IN
            ( values=singleColumnInValues { conditions.add(Pair.create(key, ColumnCondition.Raw.simpleInCondition(values))); }
            | marker=inMarker { conditions.add(Pair.create(key, ColumnCondition.Raw.simpleInCondition(marker))); }
            )
        | '[' element=term ']'
            ( op=relationType t=term { conditions.add(Pair.create(key, ColumnCondition.Raw.collectionCondition(t, element, op))); }
            | K_IN
                ( values=singleColumnInValues { conditions.add(Pair.create(key, ColumnCondition.Raw.collectionInCondition(element, values))); }
                | marker=inMarker { conditions.add(Pair.create(key, ColumnCondition.Raw.collectionInCondition(element, marker))); }
                )
            )
        )
    ;

properties[PropertyDefinitions props]
    : property[props] (K_AND property[props])*
    ;

property[PropertyDefinitions props]
    : k=noncol_ident '=' simple=propertyValue { try { $props.addProperty(k.toString(), simple); } catch (SyntaxException e) { addRecognitionError(e.getMessage()); } }
    | k=noncol_ident '=' map=mapLiteral { try { $props.addProperty(k.toString(), convertPropertyMap(map)); } catch (SyntaxException e) { addRecognitionError(e.getMessage()); } }
    ;

propertyValue returns [String str]
    : c=constant           { $str = c.getRawText(); }
    | u=unreserved_keyword { $str = u; }
    ;

relationType returns [Operator op]
    : '='  { $op = Operator.EQ; }
    | '<'  { $op = Operator.LT; }
    | '<=' { $op = Operator.LTE; }
    | '>'  { $op = Operator.GT; }
    | '>=' { $op = Operator.GTE; }
    | '!=' { $op = Operator.NEQ; }
    ;

relation[WhereClause.Builder clauses]
    : name=cident type=relationType t=term { $clauses.add(new SingleColumnRelation(name, type, t)); }
    | name=cident K_LIKE v=STRING_LITERAL { buildLIKERelation($clauses, name, $v.text); }
    | name=cident K_IS K_NOT K_NULL { $clauses.add(new SingleColumnRelation(name, Operator.IS_NOT, Constants.NULL_LITERAL)); }
    | K_TOKEN l=tupleOfIdentifiers type=relationType t=term
        { $clauses.add(new TokenRelation(l, type, t)); }
    | name=cident K_IN marker=inMarker
        { $clauses.add(new SingleColumnRelation(name, Operator.IN, marker)); }
    | name=cident K_IN inValues=singleColumnInValues
        { $clauses.add(SingleColumnRelation.createInRelation($name.id, inValues)); }
    | name=cident K_CONTAINS { Operator rt = Operator.CONTAINS; } (K_KEY { rt = Operator.CONTAINS_KEY; })?
        t=term { $clauses.add(new SingleColumnRelation(name, rt, t)); }
    | name=cident '[' key=term ']' type=relationType t=term { $clauses.add(new SingleColumnRelation(name, key, type, t)); }
    | ids=tupleOfIdentifiers
      ( K_IN
          ( '(' ')'
              { $clauses.add(MultiColumnRelation.createInRelation(ids, new ArrayList<Tuples.Literal>())); }
          | tupleInMarker=inMarkerForTuple /* (a, b, c) IN ? */
              { $clauses.add(MultiColumnRelation.createSingleMarkerInRelation(ids, tupleInMarker)); }
          | literals=tupleOfTupleLiterals /* (a, b, c) IN ((1, 2, 3), (4, 5, 6), ...) */
              {
                  $clauses.add(MultiColumnRelation.createInRelation(ids, literals));
              }
          | markers=tupleOfMarkersForTuples /* (a, b, c) IN (?, ?, ...) */
              { $clauses.add(MultiColumnRelation.createInRelation(ids, markers)); }
          )
      | type=relationType literal=tupleLiteral /* (a, b, c) > (1, 2, 3) or (a, b, c) > (?, ?, ?) */
          {
              $clauses.add(MultiColumnRelation.createNonInRelation(ids, type, literal));
          }
      | type=relationType tupleMarker=markerForTuple /* (a, b, c) >= ? */
          { $clauses.add(MultiColumnRelation.createNonInRelation(ids, type, tupleMarker)); }
      )
    | '(' relation[$clauses] ')'
    ;

inMarker returns [AbstractMarker.INRaw marker]
    : QMARK { $marker = newINBindVariables(null); }
    | ':' name=noncol_ident { $marker = newINBindVariables(name); }
    ;

tupleOfIdentifiers returns [List<ColumnIdentifier.Raw> ids]
    @init { $ids = new ArrayList<ColumnIdentifier.Raw>(); }
    : '(' n1=cident { $ids.add(n1); } (',' ni=cident { $ids.add(ni); })* ')'
    ;

singleColumnInValues returns [List<Term.Raw> terms]
    @init { $terms = new ArrayList<Term.Raw>(); }
    : '(' ( t1 = term { $terms.add(t1); } (',' ti=term { $terms.add(ti); })* )? ')'
    ;

tupleOfTupleLiterals returns [List<Tuples.Literal> literals]
    @init { $literals = new ArrayList<>(); }
    : '(' t1=tupleLiteral { $literals.add(t1); } (',' ti=tupleLiteral { $literals.add(ti); })* ')'
    ;

markerForTuple returns [Tuples.Raw marker]
    : QMARK { $marker = newTupleBindVariables(null); }
    | ':' name=noncol_ident { $marker = newTupleBindVariables(name); }
    ;

tupleOfMarkersForTuples returns [List<Tuples.Raw> markers]
    @init { $markers = new ArrayList<Tuples.Raw>(); }
    : '(' m1=markerForTuple { $markers.add(m1); } (',' mi=markerForTuple { $markers.add(mi); })* ')'
    ;

inMarkerForTuple returns [Tuples.INRaw marker]
    : QMARK { $marker = newTupleINBindVariables(null); }
    | ':' name=noncol_ident { $marker = newTupleINBindVariables(name); }
    ;

comparatorType returns [CQL3Type.Raw t]
    : n=native_type     { $t = CQL3Type.Raw.from(n); }
    | c=collection_type { $t = c; }
    | tt=tuple_type     { $t = tt; }
    | id=userTypeName   { $t = CQL3Type.Raw.userType(id); }
    | K_FROZEN '<' f=comparatorType '>'
      {
        try {
            $t = CQL3Type.Raw.frozen(f);
        } catch (InvalidRequestException e) {
            addRecognitionError(e.getMessage());
        }
      }
    | s=STRING_LITERAL
      {
        try {
            $t = CQL3Type.Raw.from(new CQL3Type.Custom($s.text));
        } catch (SyntaxException e) {
            addRecognitionError("Cannot parse type " + $s.text + ": " + e.getMessage());
        } catch (ConfigurationException e) {
            addRecognitionError("Error setting type " + $s.text + ": " + e.getMessage());
        }
      }
    ;

native_type returns [CQL3Type t]
    : K_ASCII     { $t = CQL3Type.Native.ASCII; }
    | K_BIGINT    { $t = CQL3Type.Native.BIGINT; }
    | K_BLOB      { $t = CQL3Type.Native.BLOB; }
    | K_BOOLEAN   { $t = CQL3Type.Native.BOOLEAN; }
    | K_COUNTER   { $t = CQL3Type.Native.COUNTER; }
    | K_DECIMAL   { $t = CQL3Type.Native.DECIMAL; }
    | K_DOUBLE    { $t = CQL3Type.Native.DOUBLE; }
    | K_FLOAT     { $t = CQL3Type.Native.FLOAT; }
    | K_INET      { $t = CQL3Type.Native.INET;}
    | K_INT       { $t = CQL3Type.Native.INT; }
    | K_SMALLINT  { $t = CQL3Type.Native.SMALLINT; }
    | K_TEXT      { $t = CQL3Type.Native.TEXT; }
    | K_TIMESTAMP { $t = CQL3Type.Native.TIMESTAMP; }
    | K_TINYINT   { $t = CQL3Type.Native.TINYINT; }
    | K_UUID      { $t = CQL3Type.Native.UUID; }
    | K_VARCHAR   { $t = CQL3Type.Native.VARCHAR; }
    | K_VARINT    { $t = CQL3Type.Native.VARINT; }
    | K_TIMEUUID  { $t = CQL3Type.Native.TIMEUUID; }
    | K_DATE      { $t = CQL3Type.Native.DATE; }
    | K_TIME      { $t = CQL3Type.Native.TIME; }
    ;

collection_type returns [CQL3Type.Raw pt]
    : K_MAP  '<' t1=comparatorType ',' t2=comparatorType '>'
        {
            // if we can't parse either t1 or t2, antlr will "recover" and we may have t1 or t2 null.
            if (t1 != null && t2 != null)
                $pt = CQL3Type.Raw.map(t1, t2);
        }
    | K_LIST '<' t=comparatorType '>'
        { if (t != null) $pt = CQL3Type.Raw.list(t); }
    | K_SET  '<' t=comparatorType '>'
        { if (t != null) $pt = CQL3Type.Raw.set(t); }
    ;

tuple_type returns [CQL3Type.Raw t]
    : K_TUPLE '<' { List<CQL3Type.Raw> types = new ArrayList<>(); }
         t1=comparatorType { types.add(t1); } (',' tn=comparatorType { types.add(tn); })*
      '>' { $t = CQL3Type.Raw.tuple(types); }
    ;

username
    : IDENT
    | STRING_LITERAL
    | QUOTED_NAME { addRecognitionError("Quoted strings are are not supported for user names and USER is deprecated, please use ROLE");}
    ;

// Basically the same as cident, but we need to exlude existing CQL3 types
// (which for some reason are not reserved otherwise)
non_type_ident returns [ColumnIdentifier id]
    : t=IDENT                    { if (reservedTypeNames.contains($t.text)) addRecognitionError("Invalid (reserved) user type name " + $t.text); $id = new ColumnIdentifier($t.text, false); }
    | t=QUOTED_NAME              { $id = new ColumnIdentifier($t.text, true); }
    | k=basic_unreserved_keyword { $id = new ColumnIdentifier(k, false); }
    | kk=K_KEY                   { $id = new ColumnIdentifier($kk.text, false); }
    ;

unreserved_keyword returns [String str]
    : u=unreserved_function_keyword     { $str = u; }
    | k=(K_TTL | K_COUNT | K_WRITETIME | K_KEY | K_CAST) { $str = $k.text; }
    ;

unreserved_function_keyword returns [String str]
    : u=basic_unreserved_keyword { $str = u; }
    | t=native_type              { $str = t.toString(); }
    ;

basic_unreserved_keyword returns [String str]
    : k=( K_KEYS
        | K_AS
        | K_CLUSTERING
        | K_COMPACT
        | K_STORAGE
        | K_TYPE
        | K_VALUES
        | K_MAP
        | K_LIST
        | K_FILTERING
        | K_PERMISSION
        | K_PERMISSIONS
        | K_KEYSPACES
        | K_ALL
        | K_USER
        | K_USERS
        | K_ROLE
        | K_ROLES
        | K_SUPERUSER
        | K_NOSUPERUSER
        | K_LOGIN
        | K_NOLOGIN
        | K_OPTIONS
        | K_PASSWORD
        | K_EXISTS
        | K_CUSTOM
        | K_TRIGGER
        | K_DISTINCT
        | K_CONTAINS
        | K_STATIC
        | K_FROZEN
        | K_TUPLE
        | K_FUNCTION
        | K_FUNCTIONS
        | K_AGGREGATE
        | K_SFUNC
        | K_STYPE
        | K_FINALFUNC
        | K_INITCOND
        | K_RETURNS
        | K_LANGUAGE
        | K_JSON
        | K_CALLED
        | K_INPUT
        | K_LIKE
        ) { $str = $k.text; }
    ;
