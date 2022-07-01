USE  INFO430_Proj_09
go

-- Written by: Evelyn Sun
-- Stored Procedures:
--GetEmpID
CREATE PROCEDURE uspGetEmpID
@F2 varchar(40),
@L2 varchar(40),
@BirthDate2 Date,
@EmpID INT OUTPUT
AS
SET @EmpID = (SELECT EmpID 
   FROM tblEMPLOYEE 
   WHERE EmpFname = @F2
   AND EmpLname = @L2
   AND DOB = @BirthDate2)
go

--Get RoleID 
CREATE PROCEDURE uspGetRoleID 
@Rname varchar(40),
@RoleID INT OUTPUT 
AS 
SET @RoleID = (SELECT RoleID FROM tblRole WHERE RoleName = @Rname)
GO

--Get EventID 
CREATE PROCEDURE uspGetEventID 
@E_Name varchar(50),
@EventID INT OUTPUT
AS
SET @EventID = (SELECT EventID FROM tblEVENT WHERE EventName = @E_Name)
go

--Insert into Gig 
CREATE PROCEDURE [dbo].[EsNewGig]
@F varchar(40),
@L varchar(40),
@BD Date,
@RoleName varchar(50),
@Event varchar(50)
AS
DECLARE @E_ID INT, @R_ID INT, @Ev_ID INT


EXEC uspGetEventID 
@E_Name = @Event,
@EventID = @Ev_ID OUTPUT

IF @Ev_ID IS NULL
 BEGIN
  PRINT '@Ev_ID is empty; The transaction is failed'
  RAISERROR ('@Ev_ID cannot be NULL', 11,1)
  RETURN
 END

EXEC uspGetEmpID
@F2 = @F,
@L2 = @L,
@BirthDate2 = @BD,
@EmpID = @E_ID OUTPUT

IF @E_ID IS NULL
 BEGIN
  PRINT '@E_ID is empty; The transaction is failed'
  RAISERROR ('@E_ID cannot be NULL', 11,1)
  RETURN
 END

EXEC uspGetRoleID 
@Rname = @RoleName,
@RoleID = @R_ID OUTPUT

IF @R_ID IS NULL
 BEGIN
  PRINT '@R_ID is empty; The transaction is failed'
  RAISERROR ('@R_ID cannot be NULL', 11,1)
  RETURN
 END

BEGIN TRAN G1
INSERT INTO tblGig(EventID, EmpID, RoleID)
VALUES (@Ev_ID, @E_ID, @R_ID)
IF @@ERROR <> 0
 BEGIN
  PRINT 'there is an error; time to rollback transaction'
  ROLLBACK TRAN G1
 END
ELSE
 COMMIT TRAN G1


 --Get a wrapper around the table 
CREATE PROCEDURE uspWRAPPER_newGig 
@Run INT
AS

DECLARE @EmpCount INT = (SELECT COUNT(*) FROM tblEMPLOYEE)
DECLARE @RoleCount INT = (SELECT COUNT(*) FROM tblROLE)
DECLARE @EventCount INT = (SELECT COUNT(*) FROM tblEVENT)


DECLARE @Firstname varchar(50), @Lastname varchar(50), @Birth Date 
DECLARE @Role varchar(50) 
DECLARE @EventName varchar(50) 

DECLARE @Pk INT 
DECLARE @Random INT 
WHILE @Run > 0
BEGIN


SET @PK = (SELECT RAND() * @EmpCount + 1)
SET @Firstname = (SELECT EmpFname FROM tblEMPLOYEE WHERE empID = @PK)
SET @Lastname = (SELECT EmpLname FROM tblEMPLOYEE WHERE empID = @PK)
SET @Birth = (SELECT DOB FROM tblEMPLOYEE WHERE empID = @PK)

SET @PK = (SELECT RAND() * @RoleCount + 1)
SET @Role = (SELECT RoleName FROM tblROLE WHERE RoleID = @PK)


SET @PK = (SELECT RAND() * @EventCount + 1)
SET @EventName = (SELECT EventName FROM tblEVENT WHERE EventID = @PK)


EXEC [EsNewGig]
@F = @Firstname,
@L = @Lastname,
@BD = @Birth,
@RoleName = @Role,
@Event = @EventName

SET @Run = @Run -1
END

-- Computed Columns: 
-- 1.	Calculate the total number of comments with music festivals selled by stubhub, add a column in the customer table as ‘Fname+Lname+has+ comments number + Comments! ’

CREATE FUNCTION fn_CalcComments(@PK INT)
RETURNS INT
AS 
BEGIN 
DECLARE @RET varchar(50) = (
SELECT CONCAT(C.CustFname,' ', C.CustLname, ' has ', SubQ.TotalComments,'!')
FROM tblCUSTOMER C
   JOIN tblORDER O ON C.CustID = O.CustID
   JOIN tblTICKET TI ON TI.OrderID = O.OrderID 
   JOIN tblINCIDENT_TICKET ITZ ON ITZ.TicketID = TI.TicketID 
   JOIN tblCOMMENT COZ ON ITZ.IncidentTicketID = COZ.IncidentTicketID 
JOIN (SELECT CO.CommentID, COUNT(CO.CommentID) AS TotalComments 
FROM tblCOMMENT CO 
   JOIN tblINCIDENT_TICKET IT ON IT.IncidentTicketID = CO.IncidentTicketID 
   JOIN tblTICKET T ON T.TicketID = IT.TicketID 
   JOIN tblEVENT_SELLER ES ON ES.EventSellerID = T.EventSellerID 
   JOIN tblTICKET_SELLER TS ON TS.TicketSellerID = ES.TicketSellerID 
WHERE TS.TicketSellerName = 'stubhub'
GROUP BY CO.CommentID
) AS SubQ on SubQ.CommentID = COZ.CommentID)

RETURN @RET 
END 

GO 

ALTER TABLE tblCUSTOMER 
ADD TotalComments AS (dbo.fn_CalcComments(CustID))

-- 2.	Calculate the total fees for each customer spent in the gothic festival before 2015.

CREATE FUNCTION fn_CalcToalfee(@PK INT)
RETURNS INT
AS 

BEGIN 
DECLARE @RET Numeric(11,2) = (
SELECT SUM(F.FeePrice)
FROM tblFEE F 
   JOIN tblORDER O ON O.FeeID = F.FeeID 
   JOIN tblCUSTOMER C ON C.CustID = O.CustID 
   JOIN tblTICKET T ON T.OrderID = O.OrderID 
   JOIN tblEvent_SELLER ES ON ES.EventSellerID = T.EventSellerID 
   JOIN tblEvent E ON E.EventID = ES.EventID 
   JOIN tblEvent_Type ET ON ET.EventTypeID = E.EventTypeID 
WHERE C.CustID = @PK
   AND ET.EventTypeName LIKE '%gothic%'
   AND YEAR(E.Enddate) < '2015'
)
RETURN @RET 
END 

GO 

ALTER TABLE tblCUSTOMER 
ADD TotalFeebefore2015 AS (dbo.fn_CalcToalfee(CustID))


-- Business Rules:
-- 1.	Employees who are over 70 and had an incident with incident type ‘work related’ can’t be registered to an  electric music festival event.
GO
CREATE FUNCTION fn_Employee_incident_festival()
RETURNS INTEGER
AS 
BEGIN
DECLARE @Ret INTEGER = 0

IF EXISTS(SELECT E.EmpID, E.EmpFname, E.EmpLname 
FROM tblEMPLOYEE E 
   JOIN tblGig G ON G.EmpID = E.EmpID 
   JOIN tblEvent EV ON EV.EventID = G.EventID
   JOIN tblEVENT_TYPE ET ON ET.EventTypeID = EV.EventTypeID
   JOIN tblEvent_Seller ES ON ES.EventID = EV.EventID
   JOIN tblTICKET T ON T.EventSellerID = ES.EventSellerID 
   JOIN tblINCIDENT_Ticket IT ON IT.TicketID = T.TicketID
   JOIN tblINCIDENT I ON I.IncidentID = IT.IncidentID 
   JOIN tblINCIDENT_TYPE ITY ON ITY.IncidentTypeID = I.IncidentTypeID
WHERE E.DOB < DATEADD(YEAR,-70, GetDate())
   AND ITY.IncidentTypeName LIKE 'Work related%'
   AND ET.EventTypeName = 'electronic music festival'
)
SET @Ret = 1
RETURN @Ret
END

GO 

ALTER TABLE tblEVENT WITH NoCheck
ADD CONSTRAINT Employee70_incident 
CHECK (dbo.fn_Employee_incident_festival() = 0)
2.	No performances are allowed with Ticket Seller that had less than 50 orders in Jazz festivals.
GO 
CREATE FUNCTION fn_Lessthan50_Jazz()
RETURNS INTEGER
AS 
BEGIN
DECLARE @Ret INTEGER = 0

IF EXISTS(SELECT TS.TicketSellerID, TS.TicketSellerName, COUNT(O.OrderID)
FROM tblEvent EV 
   JOIN tblEVENT_TYPE ET ON ET.EventTypeID = EV.EventTypeID
   JOIN tblEvent_Seller ES ON ES.EventID = EV.EventID
   JOIN tblTICKET_SELLER TS ON TS.TicketSellerID = ES.TicketSellerID
   JOIN tblTICKET T ON T.EventSellerID = ES.EventSellerID 
   JOIN tblORDER O ON O.OrderID = T.OrderID
WHERE ET.EventTypeName LIKE 'Jazz%'
GROUP BY TS.TicketSellerID, TS.TicketSellerName 
HAVING COUNT(O.OrderID) < 50
)
SET @Ret = 1
RETURN @Ret
END

GO 

ALTER TABLE tblPERFORMANCE WITH NoCheck
ADD CONSTRAINT Lessthan50Ticket
CHECK (dbo.fn_Lessthan50_Jazz() = 0)


-- Complex Views: 
-- 1.	List the top 10 oldest female customers that had more than 10 orders in the electric music festival who had also experienced less than 5 incidents in the past 10 years.

GO 
CREATE VIEW topFCustomer
as

SELECT TOP 10 C.CustID, C.CustFname, C.CustLname, COUNT(O.OrderID) AS NumofOrder, SubQ.IncidentNum
FROM tblCUSTOMER C
   JOIN tblGENDER G ON G.GenderID = C.GenderID
   JOIN tblORDER O ON O.CustID = C.CustID 
   JOIN tblTICKET T ON T.OrderID = O.OrderID 
   JOIN tblEVENT_SELLER ES ON ES.EventSellerID = T.EventSellerID
   JOIN tblEVENT E ON E.EventID = ES.EventID
   JOIN tblEvent_Type ET ON ET.EventTypeID = E.EventTypeID
   JOIN (
       SELECT C.CustID, C.CustFname, C.CustLname, COUNT(I.IncidentID) AS IncidentNum
	       FROM tblCUSTOMER C 
		      JOIN tblORDER O ON O.CustID = C.CustID 
			  JOIN tblTICKET T ON T.OrderID = O.OrderID
			  JOIN tblINCIDENT_TICKET IT ON IT.TicketID = T.TicketID
			  JOIN tblIncident I ON I.IncidentID = IT.IncidentID
			WHERE I.IncidentTime > DATEADD(YEAR, -10, GetDate())
			GROUP BY C.CustID, C.CustFname, C.CustLname
			HAVING COUNT(I.IncidentID) < 5
) AS SubQ ON SubQ.CustID = C.CustID 

WHERE ET.EventTypeName = 'electronic music festival'
   AND G.GenderName = 'Female'
GROUP BY C.CustID, C.CustFname, C.CustLname, SubQ.IncidentNum
HAVING COUNT(O.OrderID) > 10
ORDER BY NumofOrder DESC 
GO

SELECT * FROM topFCustomer

-- 2.	List the 3 gothic music festivals that had the least amount of fees before 2015,which also had hired less than 10 male employees with a role of security.
GO 
CREATE VIEW topGothicFestival
AS 

SELECT TOP 3 E.EventID, E.EventName, SUM(F.FeePrice) AS NumofFee, SubQ.numofSecurity 
FROM tblEVENT E 
  JOIN tblEvent_Type ET ON ET.EventTypeID = E.EventTypeID
  JOIN tblEVENT_SELLER ES ON ES.EventID = E.EventID
  JOIN tblTICKET T ON T.EventSellerID = ES.EventSellerID
  JOIN tblORDER O ON O.OrderID = T.OrderID 
  JOIN tblFEE F ON F.FeeID = O.FeeID
  JOIN(
  SELECT E.EventID, E.EventName, COUNT(EM.EmpID) AS numofSecurity
  FROM tblEvent E 
    JOIN tblGig G ON G.EventID = E.EventID 
	JOIN tblEMPLOYEE EM ON EM.EmpID = G.EmpID 
	JOIN tblGENDER GE ON GE.GenderID = EM.GenderID
	JOIN tblROLE R ON R.RoleID = G.RoleID 
  WHERE R.RoleName = 'Security'
  GROUP BY E.EventID, E.EventName
  HAVING COUNT(EM.EmpID) < 10
  )AS SubQ ON SubQ.EventID = E.EventID 
WHERE ET.EventTypeName = 'gothic festical'
  AND Year(E.BeginDate) < '2015'
GROUP BY E.EventID, E.EventName,SubQ.numofSecurity 
ORDER BY NumofFee ASC 
GO 

SELECT * FROM topGothicFestival
