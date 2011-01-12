--
-- Test large object support
--

-- Load a file
CREATE TABLE lotest_stash_values (loid oid, fd integer);
-- lo_creat(mode integer) returns oid
-- The mode arg to lo_creat is unused, some vestigal holdover from ancient times
-- returns the large object id
INSERT INTO lotest_stash_values (loid) SELECT lo_creat(42);

-- NOTE: large objects require transactions
BEGIN;

-- lo_open(lobjId oid, mode integer) returns integer
-- The mode parameter to lo_open uses two constants:
--   INV_READ  = 0x20000
--   INV_WRITE = 0x40000
-- The return value is a file descriptor-like value which remains valid for the
-- transaction.
UPDATE lotest_stash_values SET fd = lo_open(loid, CAST(x'20000' | x'40000' AS integer));

-- loread/lowrite names are wonky, different from other functions which are lo_*
-- lowrite(fd integer, data bytea) returns integer
-- the integer is the number of bytes written
SELECT lowrite(fd, '
Whose woods these are I think I know,
His house is in the village though.
He will not see me stopping here,
To watch his woods fill up with snow.

My little horse must think it queer,
To stop without a farmhouse near,
Between the woods and frozen lake,
The darkest evening of the year.

He gives his harness bells a shake,
To ask if there is some mistake.
The only other sound''s the sweep,
Of easy wind and downy flake.

The woods are lovely, dark and deep,
But I have promises to keep,
And miles to go before I sleep,
And miles to go before I sleep.

         -- Robert Frost
') FROM lotest_stash_values;

-- lo_close(fd integer) returns integer
-- return value is 0 for success, or <0 for error (actually only -1, but...)
SELECT lo_close(fd) FROM lotest_stash_values;

END;

-- Read out a portion
BEGIN;
UPDATE lotest_stash_values SET fd=lo_open(loid, CAST(x'20000' | x'40000' AS integer));

-- lo_lseek(fd integer, offset integer, whence integer) returns integer
-- offset is in bytes, whence is one of three values:
--  SEEK_SET (= 0) meaning relative to beginning
--  SEEK_CUR (= 1) meaning relative to current position
--  SEEK_END (= 2) meaning relative to end (offset better be negative)
-- returns current position in file
SELECT lo_lseek(fd, 422, 0) FROM lotest_stash_values;

-- loread/lowrite names are wonky, different from other functions which are lo_*
-- loread(fd integer, len integer) returns bytea
SELECT loread(fd, 35) FROM lotest_stash_values;

SELECT lo_lseek(fd, -19, 1) FROM lotest_stash_values;

SELECT lowrite(fd, 'n') FROM lotest_stash_values;

SELECT lo_tell(fd) FROM lotest_stash_values;

SELECT lo_lseek(fd, -156, 2) FROM lotest_stash_values;

SELECT loread(fd, 35) FROM lotest_stash_values;

SELECT lo_close(fd) FROM lotest_stash_values;

END;

-- Test resource management
BEGIN;
SELECT lo_open(loid, x'40000'::int) from lotest_stash_values;
ABORT;

-- Test truncation.
BEGIN;
UPDATE lotest_stash_values SET fd=lo_open(loid, CAST(x'20000' | x'40000' AS integer));

SELECT lo_truncate(fd, 10) FROM lotest_stash_values;
SELECT loread(fd, 15) FROM lotest_stash_values;

SELECT lo_truncate(fd, 10000) FROM lotest_stash_values;
SELECT loread(fd, 10) FROM lotest_stash_values;
SELECT lo_lseek(fd, 0, 2) FROM lotest_stash_values;
SELECT lo_tell(fd) FROM lotest_stash_values;

SELECT lo_truncate(fd, 5000) FROM lotest_stash_values;
SELECT lo_lseek(fd, 0, 2) FROM lotest_stash_values;
SELECT lo_tell(fd) FROM lotest_stash_values;

SELECT lo_close(fd) FROM lotest_stash_values;
END;

-- lo_unlink(lobjId oid) returns integer
-- return value appears to always be 1
SELECT lo_unlink(loid) from lotest_stash_values;

TRUNCATE lotest_stash_values;

INSERT INTO lotest_stash_values (loid) SELECT lo_import('/Users/masonsharp/dev/pgxc/postgres-xc/src/test/regress/data/tenk.data');

BEGIN;
UPDATE lotest_stash_values SET fd=lo_open(loid, CAST(x'20000' | x'40000' AS integer));

-- with the default BLKSZ, LOBLKSZ = 2048, so this positions us for a block
-- edge case
SELECT lo_lseek(fd, 2030, 0) FROM lotest_stash_values;

-- this should get half of the value from page 0 and half from page 1 of the
-- large object
SELECT loread(fd, 36) FROM lotest_stash_values;

SELECT lo_tell(fd) FROM lotest_stash_values;

SELECT lo_lseek(fd, -26, 1) FROM lotest_stash_values;

SELECT lowrite(fd, 'abcdefghijklmnop') FROM lotest_stash_values;

SELECT lo_lseek(fd, 2030, 0) FROM lotest_stash_values;

SELECT loread(fd, 36) FROM lotest_stash_values;

SELECT lo_close(fd) FROM lotest_stash_values;
END;

SELECT lo_export(loid, '/Users/masonsharp/dev/pgxc/postgres-xc/src/test/regress/results/lotest.txt') FROM lotest_stash_values;

\lo_import 'results/lotest.txt'

\set newloid :LASTOID

-- just make sure \lo_export does not barf
\lo_export :newloid 'results/lotest2.txt'

-- This is a hack to test that export/import are reversible
-- This uses knowledge about the inner workings of large object mechanism
-- which should not be used outside it.  This makes it a HACK
SELECT pageno, data FROM pg_largeobject WHERE loid = (SELECT loid from lotest_stash_values)
EXCEPT
SELECT pageno, data FROM pg_largeobject WHERE loid = :newloid;


SELECT lo_unlink(loid) FROM lotest_stash_values;
\lo_unlink :newloid

TRUNCATE lotest_stash_values;
