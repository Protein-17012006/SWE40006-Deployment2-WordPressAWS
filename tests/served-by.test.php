<?php
// Unit tests for the footer helpers in codedeploy/wp-content/mu-plugins/a2-served-by.php

test( 'db_label names a local MariaDB server with its short version', function () {
	assert_same( 'MariaDB 10.5.25 on this EC2 instance', a2_db_label( 'localhost', '10.5.25-MariaDB', '' ) );
} );

test( 'db_label strips the 5.5.5- prefix MariaDB sends to MySQL clients', function () {
	assert_same( 'MariaDB 10.5.25 on this EC2 instance', a2_db_label( 'localhost', '5.5.5-10.5.25-MariaDB', '' ) );
} );

test( 'db_label recognises an RDS endpoint and reports TLS', function () {
	assert_same(
		'Amazon RDS (MariaDB 11.4.5) over TLS (TLS_AES_256_GCM_SHA384)',
		a2_db_label( 'a2-wordpress-db.abc123xyz.ap-southeast-1.rds.amazonaws.com', '11.4.5-MariaDB-log', 'TLS_AES_256_GCM_SHA384' )
	);
} );

test( 'db_label recognises RDS host with port and any case', function () {
	assert_same( 'Amazon RDS (MariaDB 11.4.5)', a2_db_label( 'A2-WORDPRESS-DB.ABC.AP-SOUTHEAST-1.RDS.AMAZONAWS.COM:3306', '11.4.5-MariaDB', '' ) );
} );

test( 'db_label treats 127.0.0.1 as local and tolerates an unknown version', function () {
	assert_same( 'MariaDB on this EC2 instance', a2_db_label( '127.0.0.1', '', '' ) );
} );

test( 'served_by_text shows instance, zone and database', function () {
	assert_same(
		'Served by EC2 i-0abc123 | ap-southeast-1a | Database: Amazon RDS (MariaDB 11.4.5)',
		a2_served_by_text( array( 'instance-id' => 'i-0abc123', 'availability-zone' => 'ap-southeast-1a' ), 'Amazon RDS (MariaDB 11.4.5)' )
	);
} );

test( 'served_by_text falls back to unknown when metadata is missing', function () {
	assert_same(
		'Served by EC2 unknown | unknown | Database: MariaDB on this EC2 instance',
		a2_served_by_text( array(), 'MariaDB on this EC2 instance' )
	);
} );
