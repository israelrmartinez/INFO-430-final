USE INFO430_Proj_09
go


-- Written by: Israel Martinez

-- Stored Procedures:
-- INSERT performer
CREATE PROCEDURE uspGetPerformerTypeID
@P_Type varchar(100),
@P_TypeID INT OUTPUT
AS
SET @P_TypeID = (SELECT PerformerTypeID FROM tblPERFORMER_TYPE WHERE PerformerTypeName = @P_Type)
go

CREATE PROCEDURE INSERT_PERFORMER
@Performer_Type varchar(100),
@Performer_Name varchar(100)
AS
DECLARE @PT_ID INT

EXEC uspGetPerformerTypeID
@P_Type = @Performer_Type,
@P_TypeID = @PT_ID OUTPUT
IF @PT_ID IS NULL
	BEGIN
        PRINT 'Hi...there is an error with @PT_ID being NULL'
        RAISERROR ('@PT_ID cannot be null', 11,1)
        RETURN
    END


BEGIN TRAN G1
INSERT INTO tblPERFORMER (PerformerTypeID, PerformerName)
VALUES (@PT_ID, @Performer_Name)
IF @@ERROR <> 0
    BEGIN
        PRINT 'Hey...there is an error up ahead and I am pulling over'
        ROLLBACK TRAN G1

    END
ELSE
    COMMIT TRAN G1


-- INSERT performance
CREATE PROCEDURE uspGetEventID
@E_Name varchar(100),
@Event_ID INT OUTPUT
AS
SET @Event_ID = (SELECT EventID FROM tblEVENT WHERE EventName = @E_Name)
go

CREATE PROCEDURE uspGetPerformerID
@P_Name varchar(100),
@Performer_ID INT OUTPUT
AS
SET @Performer_ID = (SELECT PerformerID FROM tblPERFORMER WHERE PerformerName = @P_Name)
go

CREATE PROCEDURE uspGetStageID
@S_Name varchar(100),
@Stage_ID INT OUTPUT
AS
SET @Stage_ID = (SELECT StageID FROM tblSTAGE WHERE StageName = @S_Name)
go

CREATE PROCEDURE INSERT_PERFORMANCE
@Event_Name varchar(100),
@Performer_Name varchar(100),
@Stage_Name varchar(100),
@Perform_StartTime time,
@Perform_EndTime time
AS
DECLARE @E_ID INT, @P_ID INT, @S_ID INT

EXEC uspGetEventID
@E_Name = @Event_Name,
@Event_ID = @E_ID OUTPUT
IF @E_ID IS NULL
	BEGIN
        PRINT 'Hi...there is an error with @E_ID being NULL'
        RAISERROR ('@E_ID cannot be null', 11,1)
        RETURN
    END

EXEC uspGetPerformerID
@P_Name = @Performer_Name,
@Performer_ID = @P_ID OUTPUT
IF @P_ID IS NULL
	BEGIN
        PRINT 'Hi...there is an error with @P_ID being NULL'
        RAISERROR ('@P_ID cannot be null', 11,1)
        RETURN
    END

EXEC uspGetStageID
@S_Name = @Stage_Name,
@Stage_ID = @S_ID OUTPUT
IF @S_ID IS NULL
	BEGIN
        PRINT 'Hi...there is an error with @S_ID being NULL'
        RAISERROR ('@S_ID cannot be null', 11,1)
        RETURN
    END

BEGIN TRAN G1
INSERT INTO tblPERFORMANCE (EventID, PerformerID, StageID, PerformStartTime, PerformEndTime)
VALUES (@E_ID, @P_ID, @S_ID, @Perform_StartTime, @Perform_EndTime)
IF @@ERROR <> 0
    BEGIN
        PRINT 'Hey...there is an error up ahead and I am pulling over'
        ROLLBACK TRAN G1

    END
ELSE
    COMMIT TRAN G1
go


-- Computed Columns: 
--1 Calculate total number of performers at a singer/musician event
CREATE FUNCTION fn_SumSingersMusicians(@PK INT)
RETURNS INT
AS
BEGIN
	DECLARE @RET INT = (
		SELECT COUNT(PR.PerformerID) NumPerformers
		FROM tblPERFORMANCE PC
			JOIN tblEVENT EV ON EV.EventID = PC.EventID
			JOIN tblPERFORMER PR ON PR.PerformerID = PC.PerformerID
			JOIN tblPERFORMER_TYPE PT ON PT.PerformerTypeID = PR.PerformerTypeID
		WHERE PR.PerformerID = @PK AND 
		(PT.PerformerTypeName = 'Musician' OR PT.PerformerTypeName = 'Singer')
	)
	RETURN @RET
END
GO

ALTER TABLE tblPERFORMER
ADD NumOfSingersMusicians AS (dbo.fn_SumSingersMusicians(PerformerID))
GO

-- 2. Calculate sum of performance times for one orchestra event
CREATE FUNCTION fn_OrchestraSumTimes (@PK int)
RETURNS int
BEGIN
	DECLARE @RET int = (
		SELECT DATEDIFF(MINUTE, PC.PerformStartTime, PC.PerformEndTime) TotalTime
		FROM tblPERFORMANCE PC
			JOIN tblEVENT EV ON EV.EventID = PC.EventID
			JOIN tblPERFORMER PR ON PR.PerformerID = PC.PerformerID
			JOIN tblPERFORMER_TYPE PT ON PT.PerformerTypeID = PR.PerformerTypeID
		WHERE EV.EventID = @PK AND PT.PerformerTypeName = 'Orchestra'
	)
	RETURN @RET
END
GO

ALTER TABLE tblEVENT
ADD TotalOrchestraTime AS (dbo.fn_OrchestraSumTimes(EventID))
GO


-- Business Rules:
-- 1. An event with a high attendance of non-cisgendered customers should have extra security detail at the event
CREATE FUNCTION fn_HighTransAttendance()
RETURNS INTEGER
AS
BEGIN
	DECLARE @Ret INT = 0
	IF EXISTS(
		SELECT EV.EventName, COUNT(O.OrderID) NumCustomers
		FROM tblEvent EV
			JOIN tblEVENT_SELLER ES ON ES.EventID = EV.EventID
			JOIN tblTICKET T ON T.EventSellerID = ES.EventSellerID
			JOIN tblORDER O ON O.OrderID = T.OrderID
			JOIN tblCUSTOMER C ON C.CustID = O.CustID
			JOIN tblGENDER G ON G.GenderID = C.GenderID
		WHERE NOT G.GenderName = 'Male' AND NOT G.GenderName = 'Female'
		GROUP BY EventName
		HAVING COUNT(O.OrderID) > 30)
	SET @Ret = 1
	RETURN @Ret
END
GO

ALTER TABLE tblEVENT WITH NOCHECK
ADD CONSTRAINT TransAttendance
CHECK(dbo.fn_HighTransAttendance() = 0)
GO



-- 2. Performances by Musician performers must have at least 7 security employees present
CREATE FUNCTION fn_MusicianSecurity()
RETURNS INTEGER
AS
BEGIN
	DECLARE @Ret INT = 0
	DECLARE @RoleID INT = (SELECT RoleID from tblROLE WHERE RoleName = 'Security')
	IF EXISTS(
		SELECT PC.PerformanceID, PT.PerformerTypeName
		FROM tblPERFORMER_TYPE PT
			JOIN tblPERFORMER PR ON PT.PerformerTypeID = PR.PerformerTypeID
			JOIN tblPERFORMANCE PC ON PC.PerformerID = PR.PerformerID
			JOIN tblEVENT EV ON EV.EventID = PC.PerformanceID
			JOIN tblGIG G ON G.EventID = EV.EventID
		WHERE PT.PerformerTypeName = 'Musician'	AND G.RoleID = @RoleID
		GROUP BY PC.PerformanceID, PT.PerformerTypeName
		HAVING COUNT(G.GigID) < 7)
	SET @Ret = 1
	RETURN @Ret
END
GO

ALTER TABLE tblPERFORMANCE WITH NOCHECK
ADD CONSTRAINT SevenOrMoreSecurity
CHECK(dbo.fn_MusicianSecurity() = 0)
