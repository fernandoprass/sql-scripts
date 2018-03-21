-- =====================================================================
-- Author: Fernando Prass | Create date: 09/04/2017
-- Language: ANSI SQL for MySQL 5.1+
-- Description: Create a recursive procedure to return records from a self-referenced table
-- Note 1: This procedure leaves in memory a table called hierarchy
-- Note 2: The "contador" parameter should be started as 0 (zero)
-- Contact: https://gitlab.com/fernando.prass or https://twitter.com/oFernandoPrass
-- =====================================================================

CREATE TABLE `SUBJECT ` (
  `ID_SUBJECT ` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `DESCRIPTION` varchar(150) NOT NULL,
  `ID_SUBJECT_MASTER` int(10) unsigned DEFAULT NULL,
  PRIMARY KEY (`ID_SUBJECT `),
  KEY `FK_SUBJECT_SUBJECT_idx` (`ID_SUBJECT_MASTER`),
  CONSTRAINT `FK_SUBJECT _SUBJECT _MASTER` FOREIGN KEY (`ID_SUBJECT_MASTER`) REFERENCES `SUBJECT ` (`ID_SUBJECT `) ON DELETE NO ACTION ON UPDATE NO ACTION
) ENGINE=InnoDB AUTO_INCREMENT=38 DEFAULT CHARSET=utf8;

INSERT INTO `SUBJECT ` VALUES (1,'Biologia',NULL),(2,'1. Estudo da Biologia',1),(3,'1.1. Conceito de Biologia',2),(4,'1.2. Níveis de organização dos seres vivos',2),(5,'1.3. Subdivisões da Biologia',2),(7,'2. Química Celular',1),(8,'2.1. Componentes inorgânicos',7),(11,'2.2. Componentes orgânicos',7);



/**************************************************/

CREATE DEFINER=`myDatabase`@`%` PROCEDURE `spAssuntoGetHierarquiaRecursiva`(idSubject int, counter int)
BEGIN  
	declare idSubjectMaster int;
    
    SET counter = IFNULL(counter, 0);
    
    if (counter = 0) then
		DROP TABLE IF EXISTS hierarquia;
        set counter = 1;
	else
		set counter = counter + 1;
    end if;    
      
	CREATE TEMPORARY TABLE IF NOT EXISTS hierarchy
    (  ID_SUBJECT  int
      , DESCRIPTION varchar(150)
      , ID_SUBJECT_MASTER int
	) ENGINE=MEMORY ;

	insert into hierarchy
	select ID_SUBJECT , DESCRIPTION, ID_SUBJECT_MASTER
	from SUBJECT 
	where ID_SUBJECT  = idSubject; 
      
	select ID_SUBJECT_MASTER
    into idSubjectMaster
	from SUBJECT 
	where ID_SUBJECT  = idSubject;
    
    /* Recursively call the function until the idSubjectMaster is NULL */
    if (idSubjectMaster is not null) then
		call spSubjectGetHierarchy(idSubjectMaster, counter);
	end if;
END

CREATE DEFINER=`myDatabase`@`%` PROCEDURE `spSubjectGetHierarchy`(idSubject int)
BEGIN     
    declare nome varchar(150);
	declare idSubjectMaster int default 0;
    declare nivelHierarquico int default 1;
    
    DROP TABLE IF EXISTS hierarchy;
    
	CREATE TEMPORARY TABLE IF NOT EXISTS hierarchy
    (   ID_SUBJECT  int
      , DESCRIPTION varchar(150)
      , ID_SUBJECT_MASTER int
      , NIVEL int
	) ENGINE=MEMORY ;
    
    WHILE idSubjectMaster is not null DO    	
		select DESCRIPTION, ID_SUBJECT_MASTER
        into nome, idSubjectMaster
		from SUBJECT 
		where ID_SUBJECT  = idSubject; 
        
        insert into hierarchy (ID_SUBJECT , DESCRIPTION, ID_SUBJECT_MASTER, NIVEL)
        values (idSubject, nome, idSubjectMaster, hierarchicalLevel);
        
		if (idSubjectMaster is not null) then
			set idSubject = idSubjectMaster;
            set hierarchicalLevel = hierarchicalLevel + 1;
		end if;
	END WHILE;
    
    /* update SUBJECT hierarchical level  */    
    SET SQL_SAFE_UPDATES = 0;
    
    set hierarchicalLevel = hierarchicalLevel + 1;
    
    update hierarchy
    set NIVEL = hierarchicalLevel - NIVEL;
    
    SET SQL_SAFE_UPDATES = 1;
END
