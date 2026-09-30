<?php
/**
 * Plugin Name: A2 Served By
 * Description: SWE40006 Deployment Activity 2 - shows which EC2 instance, Availability Zone and database served the page.
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

/**
 * "10.5.25-MariaDB" -> "10.5.25". MariaDB prefixes "5.5.5-" when it talks to MySQL clients; that prefix is dropped.
 */
function a2_short_version( string $version ): string {
	$version = (string) preg_replace( '/^5\.5\.5-(?=\d)/', '', $version );
	return preg_match( '/^\d+(?:\.\d+){0,2}/', $version, $m ) ? $m[0] : '';
}

/**
 * Human-readable description of the database WordPress is connected to.
 */
function a2_db_label( string $db_host, string $server_version, string $tls_cipher ): string {
	$version = a2_short_version( $server_version );
	$engine  = $version === '' ? 'MariaDB' : "MariaDB $version";
	$is_rds  = (bool) preg_match( '/\.rds\.amazonaws\.com(?::\d+)?$/i', $db_host );
	$label   = $is_rds ? "Amazon RDS ($engine)" : "$engine on this EC2 instance";
	return $tls_cipher === '' ? $label : "$label over TLS ($tls_cipher)";
}

/**
 * Footer text; metadata that could not be read shows as "unknown".
 */
function a2_served_by_text( array $meta, string $db_label ): string {
	$id = isset( $meta['instance-id'] ) && $meta['instance-id'] !== '' ? $meta['instance-id'] : 'unknown';
	$az = isset( $meta['availability-zone'] ) && $meta['availability-zone'] !== '' ? $meta['availability-zone'] : 'unknown';
	return "Served by EC2 $id | $az | Database: $db_label";
}

/**
 * Instance ID and Availability Zone from IMDSv2, with 1 s timeouts. Cached for this request only: the database
 * is shared by every instance, so a transient would show one instance's ID on all of them.
 */
function a2_instance_meta(): array {
	static $meta = null;
	if ( $meta !== null ) {
		return $meta;
	}
	$meta  = array();
	$token = wp_remote_request(
		'http://169.254.169.254/latest/api/token',
		array(
			'method'  => 'PUT',
			'timeout' => 1,
			'headers' => array( 'X-aws-ec2-metadata-token-ttl-seconds' => '60' ),
		)
	);
	if ( is_wp_error( $token ) || 200 !== (int) wp_remote_retrieve_response_code( $token ) ) {
		return $meta;
	}
	$headers = array( 'X-aws-ec2-metadata-token' => wp_remote_retrieve_body( $token ) );
	foreach ( array( 'instance-id', 'placement/availability-zone' ) as $path ) {
		$response = wp_remote_get( 'http://169.254.169.254/latest/meta-data/' . $path, array( 'timeout' => 1, 'headers' => $headers ) );
		if ( ! is_wp_error( $response ) && 200 === (int) wp_remote_retrieve_response_code( $response ) ) {
			$meta[ basename( $path ) ] = trim( wp_remote_retrieve_body( $response ) );
		}
	}
	return $meta;
}

function a2_render_served_by(): void {
	global $wpdb;
	$cipher = '';
	$row    = $wpdb->get_row( "SHOW SESSION STATUS LIKE 'Ssl_cipher'" );
	if ( $row && isset( $row->Value ) ) {
		$cipher = (string) $row->Value;
	}
	$label = a2_db_label( DB_HOST, (string) $wpdb->db_server_info(), $cipher );
	printf(
		'<div id="a2-served-by" style="position:fixed;left:0;right:0;bottom:0;z-index:99999;padding:6px 12px;background:#232f3e;color:#fff;font:13px/1.4 Consolas,monospace;text-align:center">%s</div>',
		esc_html( a2_served_by_text( a2_instance_meta(), $label ) )
	);
}
add_action( 'wp_footer', 'a2_render_served_by' );
