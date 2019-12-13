CREATE OR REPLACE PROCEDURE WSO2_REG_LOG_CLEANUP
IS
-- ------------------------------------------
-- CONFIGURABLE VARIABLES
-- ------------------------------------------
batchSize INT := 10000;      -- SET BATCH SIZE FOR AVOID TABLE LOCKS    [DEFAULT : 10000]
chunkSize INT := 500000;    -- SET TEMP TABLE CHUNK SIZE FOR AVOID TABLE LOCKS    [DEFAULT : 500000]
sleepTime FLOAT := 5;          -- Sleep time in seconds.[DEFAULT : 2]
checkCount INT := 500; -- SET CHECK COUNT FOR FINISH CLEANUP SCRIPT (CLEANUP ELIGIBLE COUNT SHOULD BE HIGHER THAN checkCount TO CONTINUE) [DEFAULT : 1000]
backupTables BOOLEAN := TRUE;    -- SET TRUE IF REG PROPERTIES TO BACKUP BEFORE DELETE [DEFAULT : FALSE]. WILL DROP THE PREVIOUS BACKUP TABLES IN NEXT ITERATION
enableLog BOOLEAN := TRUE ; -- ENABLE LOGGING [DEFAULT : TRUE]
logLevel VARCHAR(10) := 'TRACE'; -- SET LOG LEVELS : TRACE , DEBUG
rowCount INT := 0;
CURRENT_SCHEMA VARCHAR(20);
cleanupCount INT := 0;
chunkCount INT := 0;
batchCount INT := 0;
backupTable VARCHAR(50);
cursorTable VARCHAR(50);

CURSOR backupTablesCursor is
SELECT TABLE_NAME FROM ALL_TABLES WHERE OWNER = CURRENT_SCHEMA AND
TABLE_NAME IN ('REG_LOG');

BEGIN
-- ------------------------------------------------------
-- CREATING LOG TABLE REG_LOG_CLEANUP
-- ------------------------------------------------------

SELECT SYS_CONTEXT( 'USERENV', 'CURRENT_SCHEMA' ) INTO CURRENT_SCHEMA FROM DUAL;

IF (enableLog)
THEN
SELECT COUNT(*) INTO rowCount from ALL_TABLES where OWNER = CURRENT_SCHEMA AND table_name = upper('LOG_WSO2_REG_LOG_CLEANUP_SP');
    IF (rowCount = 1) then
    EXECUTE IMMEDIATE 'DROP TABLE LOG_WSO2_REG_LOG_CLEANUP_SP';
    COMMIT;
    END if;
EXECUTE IMMEDIATE 'CREATE TABLE LOG_WSO2_REG_LOG_CLEANUP_SP (TIMESTAMP VARCHAR(250) , LOG VARCHAR(250)) NOLOGGING';
COMMIT;
EXECUTE IMMEDIATE 'INSERT INTO LOG_WSO2_REG_LOG_CLEANUP_SP (TIMESTAMP,LOG) VALUES (TO_CHAR( SYSTIMESTAMP, ''DD.MM.YYYY HH24:MI:SS:FF4''),''WSO2_REG_LOG_CLEANUP_SP STARTED .... !'')';
EXECUTE IMMEDIATE 'INSERT INTO LOG_WSO2_REG_LOG_CLEANUP_SP (TIMESTAMP,LOG) VALUES (TO_CHAR( SYSTIMESTAMP, ''DD.MM.YYYY HH24:MI:SS:FF4''),'' '')';
EXECUTE IMMEDIATE 'INSERT INTO LOG_WSO2_REG_LOG_CLEANUP_SP (TIMESTAMP,LOG) VALUES (TO_CHAR( SYSTIMESTAMP, ''DD.MM.YYYY HH24:MI:SS:FF4''),''USING SCHEMA :'||CURRENT_SCHEMA||''')';
COMMIT;
END IF;


-- ------------------------------------------------------
-- BACKUP TABLES
-- ------------------------------------------------------


IF (backupTables)
THEN
      IF (enableLog)
      THEN
          EXECUTE IMMEDIATE 'INSERT INTO LOG_WSO2_REG_LOG_CLEANUP_SP (TIMESTAMP,LOG) VALUES (TO_CHAR( SYSTIMESTAMP, ''DD.MM.YYYY HH24:MI:SS:FF4''),''TABLE BACKUP STARTED ... !'')';
          COMMIT;
      END IF;

      FOR cursorTable IN backupTablesCursor
      LOOP

      SELECT REPLACE(''||cursorTable.TABLE_NAME||'','REG_LOG','REG_LOG_BACKUP') INTO backupTable FROM DUAL;

      IF (enableLog AND logLevel IN ('TRACE'))
      THEN
          EXECUTE IMMEDIATE 'INSERT INTO LOG_WSO2_REG_LOG_CLEANUP_SP (TIMESTAMP,LOG) VALUES (TO_CHAR( SYSTIMESTAMP, ''DD.MM.YYYY HH24:MI:SS:FF4''),''BACKING UP TABLE OF '||cursorTable.TABLE_NAME||' CREATING AS '||backupTable||''')';
          COMMIT;
      END IF;

      SELECT COUNT(*) INTO rowCount from ALL_TABLES where OWNER = CURRENT_SCHEMA AND table_name = upper(backupTable);
      IF (ROWCOUNT = 1)
      THEN
          EXECUTE IMMEDIATE 'DROP TABLE '||backupTable;
          COMMIT;
      END if;

      EXECUTE IMMEDIATE 'CREATE TABLE '||backupTable||' AS (SELECT * FROM '||cursorTable.TABLE_NAME||' WHERE 1 = 2)';
      COMMIT;

      IF (enableLog  AND logLevel IN ('TRACE','DEBUG') )
      THEN
          EXECUTE IMMEDIATE 'INSERT INTO LOG_WSO2_REG_LOG_CLEANUP_SP (TIMESTAMP,LOG) VALUES (TO_CHAR( SYSTIMESTAMP, ''DD.MM.YYYY HH24:MI:SS:FF4''),''BACKING UP TABLE CREATION FOR '||cursorTable.TABLE_NAME||' COMPLETED '')';
          COMMIT;
      END IF;

      END LOOP;
      IF (enableLog)
      THEN
          EXECUTE IMMEDIATE 'INSERT INTO LOG_WSO2_REG_LOG_CLEANUP_SP (TIMESTAMP,LOG) VALUES (TO_CHAR( SYSTIMESTAMP, ''DD.MM.YYYY HH24:MI:SS:FF4''),'' '')';
          COMMIT;
      END IF;
END IF;


-- ------------------------------------------
-- PURGE REG_LOG
-- ------------------------------------------
LOOP

BEGIN
   EXECUTE IMMEDIATE 'DROP TABLE REG_LOG_CHUNK_TMP';
EXCEPTION
   WHEN OTHERS THEN
      IF SQLCODE != -942 THEN
         RAISE;
      END IF;
END;

EXECUTE IMMEDIATE 'CREATE TABLE REG_LOG_CHUNK_TMP AS SELECT REG_LOG_ID FROM (
  (SELECT RL.REG_LOG_ID FROM REG_LOG RL LEFT JOIN (
  SELECT MAX(REG_LOG_ID) AS REG_LOG_ID FROM REG_LOG GROUP BY REG_PATH, REG_TENANT_ID) X
  ON RL.REG_LOG_ID = X.REG_LOG_ID
  WHERE X.REG_LOG_ID IS NULL)
  UNION
  (SELECT REG_LOG_ID FROM REG_LOG WHERE REG_ACTION = 7)
    ) A WHERE rownum <= '||batchSize||'' ;

chunkCount := SQL%rowcount;

IF (chunkCount < checkCount OR chunkCount=0)
THEN
IF (chunkCount < checkCount)
THEN
EXECUTE IMMEDIATE 'INSERT INTO LOG_WSO2_REG_LOG_CLEANUP_SP (TIMESTAMP,LOG) VALUES (TO_CHAR( SYSTIMESTAMP, ''DD.MM.YYYY HH24:MI:SS:FF4''),''EXIT LOOP HENCE DELETE ELIGIBLE COUNT IS LESS THAN CHECK_COUNT DEFINED'')';
EXECUTE IMMEDIATE 'INSERT INTO LOG_WSO2_REG_LOG_CLEANUP_SP (TIMESTAMP,LOG) VALUES (TO_CHAR( SYSTIMESTAMP, ''DD.MM.YYYY HH24:MI:SS:FF4''),''DELETE ELIGIBLE : '||chunkCount||''')';
EXECUTE IMMEDIATE 'INSERT INTO LOG_WSO2_REG_LOG_CLEANUP_SP (TIMESTAMP,LOG) VALUES (TO_CHAR( SYSTIMESTAMP, ''DD.MM.YYYY HH24:MI:SS:FF4''),''CHECK COUNT : '||checkCount||''')';
END IF;
EXIT;
END IF;


IF (enableLog AND logLevel IN ('DEBUG','TRACE'))
THEN
EXECUTE IMMEDIATE 'INSERT INTO LOG_WSO2_REG_LOG_CLEANUP_SP (TIMESTAMP,LOG) VALUES (TO_CHAR( SYSTIMESTAMP, ''DD.MM.YYYY HH24:MI:SS:FF4''),''REG_LOG_CHUNK_TMP TABLE CREATED WITH : '||checkCount||''')';
END IF;

EXECUTE IMMEDIATE 'CREATE INDEX REG_LOG_CHUNK_TMP_INDX on REG_LOG_CHUNK_TMP (REG_LOG_ID)';

COMMIT;

        LOOP

        BEGIN
           EXECUTE IMMEDIATE 'DROP TABLE REG_LOG_BATCH_TMP';
        EXCEPTION
           WHEN OTHERS THEN
              IF SQLCODE != -942 THEN
                 RAISE;
              END IF;
        END;

        EXECUTE IMMEDIATE 'CREATE TABLE REG_LOG_BATCH_TMP AS SELECT REG_LOG_ID FROM REG_LOG_CHUNK_TMP WHERE rownum <= '||batchSize||'';

        batchCount := SQL%rowcount;

		IF (batchCount=0)
        THEN
        EXIT;
        END IF;

        IF (backupTables)
        THEN
        IF (enableLog AND logLevel IN ('TRACE'))
        THEN
        EXECUTE IMMEDIATE 'INSERT INTO LOG_WSO2_REG_LOG_CLEANUP_SP (TIMESTAMP,LOG) VALUES (TO_CHAR( SYSTIMESTAMP, ''DD.MM.YYYY HH24:MI:SS:FF4''),''BACKING UP TABLE REG_LOG_BACKUP'')';
        END IF;
        EXECUTE IMMEDIATE 'INSERT INTO REG_LOG_BACKUP SELECT RL.* FROM  REG_LOG RL INNER JOIN  REG_LOG_BATCH_TMP  RLB ON RL.REG_LOG_ID = RLB.REG_LOG_ID';
        COMMIT;
        END IF;

        IF (enableLog AND logLevel IN ('TRACE'))
        THEN
        EXECUTE IMMEDIATE 'INSERT INTO LOG_WSO2_REG_LOG_CLEANUP_SP (TIMESTAMP,LOG) VALUES (TO_CHAR( SYSTIMESTAMP, ''DD.MM.YYYY HH24:MI:SS:FF4''),''BATCH DELETE STARTED ON REG_LOG: '||batchCount||''')';
        END IF;

        EXECUTE IMMEDIATE 'DELETE FROM REG_LOG where REG_LOG_ID IN (SELECT REG_LOG_ID FROM REG_LOG_BATCH_TMP)';

        rowCount := SQL%rowcount;
		COMMIT;
        IF (enableLog AND logLevel IN ('DEBUG','TRACE'))
        THEN
        EXECUTE IMMEDIATE 'INSERT INTO LOG_WSO2_REG_LOG_CLEANUP_SP (TIMESTAMP,LOG) VALUES (TO_CHAR( SYSTIMESTAMP, ''DD.MM.YYYY HH24:MI:SS:FF4''),''BATCH DELETE FINISHED ON REG_LOG:  '||rowCount||''')';
        END IF;

        IF (enableLog AND logLevel IN ('TRACE'))
        THEN
        EXECUTE IMMEDIATE 'INSERT INTO LOG_WSO2_REG_LOG_CLEANUP_SP (TIMESTAMP,LOG) VALUES (TO_CHAR( SYSTIMESTAMP, ''DD.MM.YYYY HH24:MI:SS:FF4''),''BATCH DELETE STARTED ON REG_LOG_CHUNK_TMP :  '||batchCount||''')';
        END IF;

        EXECUTE IMMEDIATE 'DELETE FROM REG_LOG_CHUNK_TMP where REG_LOG_ID IN (SELECT REG_LOG_ID FROM REG_LOG_BATCH_TMP)';

		COMMIT;
        IF (enableLog AND logLevel IN ('TRACE'))
        THEN
        EXECUTE IMMEDIATE 'INSERT INTO LOG_WSO2_REG_LOG_CLEANUP_SP (TIMESTAMP,LOG) VALUES (TO_CHAR( SYSTIMESTAMP, ''DD.MM.YYYY HH24:MI:SS:FF4''),''BATCH DELETE FINISHED ON REG_LOG_CHUNK_TMP'')';
        END IF;

        IF ((rowCount > 0))
        THEN
            IF (enableLog AND logLevel IN ('TRACE'))
        THEN
        EXECUTE IMMEDIATE 'INSERT INTO LOG_WSO2_REG_LOG_CLEANUP_SP (TIMESTAMP,LOG) VALUES (TO_CHAR( SYSTIMESTAMP, ''DD.MM.YYYY HH24:MI:SS:FF4''),''SLEEPING FOR SECONDS :  '||sleepTime||''')';
        END IF;
        dbms_lock.sleep(sleeptime);
        END IF;
        END LOOP;

END LOOP;

-- CLEANUP ANY EXISTING TEMP TABLES
IF (enableLog AND logLevel IN ('TRACE'))
THEN
EXECUTE IMMEDIATE 'INSERT INTO LOG_WSO2_REG_LOG_CLEANUP_SP (TIMESTAMP,LOG) VALUES (TO_CHAR( SYSTIMESTAMP, ''DD.MM.YYYY HH24:MI:SS:FF4''),''DROP TEMP TABLES REG_LOG_CHUNK_TMP'')';
BEGIN
   EXECUTE IMMEDIATE 'DROP TABLE REG_LOG_CHUNK_TMP';
EXCEPTION
   WHEN OTHERS THEN
      IF SQLCODE != -942 THEN
         RAISE;
      END IF;
END;
BEGIN
   EXECUTE IMMEDIATE 'DROP TABLE REG_LOG_BATCH_TMP';
EXCEPTION
   WHEN OTHERS THEN
      IF SQLCODE != -942 THEN
         RAISE;
      END IF;
END;
END IF;

-- ------------------------------------------------------
-- CALCULATING REG_LOG
-- ------------------------------------------------------
IF (enableLog AND logLevel IN ('DEBUG','TRACE'))
THEN
    SELECT  COUNT(1) into rowCount FROM REG_LOG;
    EXECUTE IMMEDIATE 'INSERT INTO LOG_WSO2_REG_LOG_CLEANUP_SP (TIMESTAMP,LOG) VALUES (TO_CHAR( SYSTIMESTAMP, ''DD.MM.YYYY HH24:MI:SS:FF4''),''TOTAL REG_LOG TABLE AFTER DELETE :  '||rowCount||''')';
END IF;

IF (enableLog)
THEN
EXECUTE IMMEDIATE 'INSERT INTO LOG_WSO2_REG_LOG_CLEANUP_SP (TIMESTAMP,LOG) VALUES (TO_CHAR( SYSTIMESTAMP, ''DD.MM.YYYY HH24:MI:SS:FF4''),''WSO2_REG_LOG_CLEANUP TASK COMPLETED .... !'')';
END IF;
END;