<?php
// Dependency-free test runner for the WordPress mu-plugin helpers:  php tests/run.php
define( 'ABSPATH', __DIR__ . '/' );

// WordPress stub: the plugin registers its footer hook when it is loaded.
function add_action( ...$args ) {}

$tests = array();

function test( string $name, callable $fn ): void {
	global $tests;
	$tests[ $name ] = $fn;
}

function assert_same( $expected, $actual ): void {
	if ( $expected !== $actual ) {
		throw new RuntimeException( 'expected ' . var_export( $expected, true ) . ', got ' . var_export( $actual, true ) );
	}
}

require __DIR__ . '/../codedeploy/wp-content/mu-plugins/a2-served-by.php';
foreach ( glob( __DIR__ . '/*.test.php' ) as $file ) {
	require $file;
}

$failed = 0;
foreach ( $tests as $name => $fn ) {
	try {
		$fn();
		echo "PASS  $name\n";
	} catch ( Throwable $e ) {
		$failed++;
		echo "FAIL  $name\n      " . $e->getMessage() . "\n";
	}
}
$total = count( $tests );
echo "\n" . ( $total - $failed ) . " passed, $failed failed, $total total\n";
exit( $failed === 0 ? 0 : 1 );
