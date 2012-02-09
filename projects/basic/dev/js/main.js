/*jslint browser: true, sloppy: true, white: true, nomen: false, plusplus: true, maxerr: 50, indent: 4 */
/** 
 * @depends handlebars.js
 * @depends prettydate.js
 * @depends twitter-text.js
 * @depends massrel.js
 * @depends handlebars_helpers.js
 * @depends uilist.js
 */

/* Compile Template */
function templateFromScript(selector) {
	return Handlebars.compile($(selector).text());
};

function app() {
	massrel.handlebars.register(Handlebars);

	var elStream = $('#stream');
	var uiStream = new massrel.UIList(elStream, {
		limit: 6,
		renderer: templateFromScript('#tmpl-status-twitter')
	});
	var stream = new massrel.Stream(elStream.attr('data-stream-name'));

	stream.poller({
		frequency: 15
	}).each(function(status) {
		var context = massrel.Context.create(status);
		if(context.known) {
			uiStream.prepend(context);
		}
	}).start();
}

jQuery(document).ready(app);
