SELECT 
  MAX(DBMS_LOB.GETLENGTH(xml_clob))     AS max_lob_length_bytes,
  MIN(DBMS_LOB.GETLENGTH(xml_clob))     AS min_lob_length_bytes,
  ROUND(AVG(DBMS_LOB.GETLENGTH(xml_clob))/1024/1024,2) AS avg_lob_mb,
  COUNT(*)                              AS total_rows
FROM my_schema.my_table;

      SELECT SUM(DBMS_LOB.GETLENGTH(xmlcol.getClobVal())) AS total_bytes,
       ROUND(SUM(DBMS_LOB.GETLENGTH(xmlcol.getClobVal()))/1024/1024,2) AS total_mb
FROM your_table;


      SELECT LENGTHB(x.xmlcol.getStringVal()) AS xml_length_bytes
FROM your_table x;
