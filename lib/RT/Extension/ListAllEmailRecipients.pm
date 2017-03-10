use strict;
use warnings;
package RT::Extension::ListAllEmailRecipients;

our $VERSION = '0.03';

=head1 NAME

RT-Extension-ListAllEmailRecipients - Determine all recipients for a
notification and provide emails via template variables

=head1 DESCRIPTION

ListAllEmailRecipients does a dry run of all scrips configured for a
notification to determine the full list of email receipients. This
list is then made available to templates when the actual notification
scrips are subsequently run to send email.

=head1 RT VERSION

Works with RT 4.2

=head1 INSTALLATION

=over

=item C<perl Makefile.PL>

=item C<make>

=item C<make install>

May need root permissions

=item Edit your F</opt/rt4/etc/RT_SiteConfig.pm>

Add these lines, both are required:

    Plugin('RT::Extension::ListAllEmailRecipients');
    Set(@MailPlugins, qw(Auth::MailFrom Action::ListAllEmailRecipients));

=item Clear your mason cache

    rm -rf /opt/rt4/var/mason_data/obj

=item Restart your webserver

=item Modify your templates as described below.

=back

=head1 USAGE

ListEmailReceipients adds the following template variables containing
a list of all recipients for that type for the current transaction
(comment, correspond, etc.) across all enabled notification scrips.

    $NotificationRecipientsTo
    $NotificationRecipientsCc
    $NotificationRecipientsBcc

To include these in an outgoing email, like the Admin email to AdminCcs
on a ticket, add something like the following to the appropriate template:

    <p>Email was sent to the following addresses:</p>

    <p>To: {$NotificationRecipientsTo} </p>
    <p>Cc: {$NotificationRecipientsCc} </p>
    <p>Bcc: {$NotificationRecipientsBcc} </p>

=head2 Ticket and Transaction IDs

This extension generates the recipient lists by doing a trial run of the
incoming action (create, comment, or reply). In doing so, it doesn't actually
make any changes, but it does increment the ids in the ticket and transaction
tables and possibly others depending on your scrips. This shouldn't matter for
most users since ticket ids are arbitrary, but some users depend on ticket ids
for various reasons. If you have processes that depend on specific ticket ids,
be aware that using this extension will create gaps between ticket and other
ids in your database.

=head1 AUTHOR

Best Practical Solutions, LLC E<lt>modules@bestpractical.comE<gt>

=head1 BUGS

Contact Best Practical Solutions at contact@bestpractical.com with
questions about this extension.

=head1 LICENSE AND COPYRIGHT

This software is Copyright (c) 2016 by Best Practical Solutions, LLC

This is free software, licensed under:

  The GNU General Public License, Version 2, June 1991

=cut

our $NotificationRecipientsTo;
our $NotificationRecipientsCc;
our $NotificationRecipientsBcc;

sub FindNotificationRecipients {
    my %args = (
        TicketId => undef,
        @_
    );

    $NotificationRecipientsTo = '';
    $NotificationRecipientsCc = '';
    $NotificationRecipientsBcc = '';

    my $recipients_ref = ProcessScripDryRun(%args);
    $NotificationRecipientsTo = join ', ', @{$recipients_ref->{'To'}} if $recipients_ref->{'To'};
    $NotificationRecipientsCc = join ', ', @{$recipients_ref->{'Cc'}} if $recipients_ref->{'Cc'};
    $NotificationRecipientsBcc = join ', ', @{$recipients_ref->{'Bcc'}} if $recipients_ref->{'Bcc'};

    return;
}

# Code copied from ShowSimplifiedRecipients and modified

sub ProcessScripDryRun {
    my %args = (
        UpdateInterface => 'Web',
        @_);

    RT::Logger->debug("Starting dry run to gather recipients");

    my @dryrun;

    if ( $args{'UpdateInterface'} eq 'EmailCreate' ) {
        # load separate ticket obj for dry-run
        my $TicketObj = RT::Ticket->new($args{'Ticket'}->CurrentUser);
        @dryrun = $TicketObj->DryRun(
            sub {
                $TicketObj->Create(
                    Queue     => $args{'Queue'},
                    Subject   => $args{'Subject'},
                    Requestor => $args{'Requestor'},
                    Cc        => $args{'Cc'},
                    MIMEObj   => $args{'MIMEObj'},
                );
            }
        );
    }
    elsif ( $args{'UpdateInterface'} eq 'Email' ){
        # load separate ticket obj for dry-run
        my $TicketObj = RT::Ticket->new($args{'CurrentUser'});
        my ($ret, $msg) = $TicketObj->Load($args{Ticket}->Id);

        unless ( $ret ){
            RT::Logger->error("Unable to load ticket " . $args{'Ticket'}->Id . ". Skipping dry run.");
            return;
        }

        my $action = ucfirst $args{Action};
        @dryrun = $TicketObj->DryRun(
            sub {
                my ( $status, $msg ) = $TicketObj->$action( MIMEObj => $args{Message} );
            }
        );
    }
    elsif ( $args{'id'} and $args{'id'} eq 'new' ){
        return unless $args{'TicketObj'};
        # load separate ticket obj for dry-run
        my $TicketObj = RT::Ticket->new($args{CurrentUser});

        @dryrun = $TicketObj->DryRun(
            sub {
                local $args{UpdateContent} ||= "Content";
                HTML::Mason::Commands::CreateTicket( %args );
            }
        );

    }
    else{
        # load separate ticket obj for dry-run
        my $TicketObj = RT::Ticket->new($args{'CurrentUser'});
        my ($ret, $msg) = $TicketObj->Load($args{'TicketId'});

        unless ( $ret ){
            RT::Logger->error("Unable to load ticket " . $args{'TicketId'} . ". Skipping dry run.");
            return;
        }

        @dryrun = $TicketObj->DryRun(
            sub {
                local $args{UpdateContent} ||= "Content";
                HTML::Mason::Commands::ProcessUpdateMessage(ARGSRef  => \%args, TicketObj => $TicketObj, KeepAttachments => 1 );
                HTML::Mason::Commands::ProcessTicketWatchers(ARGSRef => \%args, TicketObj => $TicketObj );
                HTML::Mason::Commands::ProcessTicketBasics(  ARGSRef => \%args, TicketObj => $TicketObj );
                HTML::Mason::Commands::ProcessTicketLinks(   ARGSRef => \%args, TicketObj => $TicketObj );
                HTML::Mason::Commands::ProcessTicketDates(   ARGSRef => \%args, TicketObj => $TicketObj );
                HTML::Mason::Commands::ProcessObjectCustomFieldUpdates(ARGSRef => \%args, TicketObj => $TicketObj );
                HTML::Mason::Commands::ProcessTicketReminders( ARGSRef => \%args, TicketObj => $TicketObj );
            }
        );
    }
    return unless @dryrun;

    my %headers = (To => {}, Cc => {}, Bcc => {});
    my %no_squelch = (To => {}, Cc => {}, Bcc => {});
    my @scrips = map {@{$_->Scrips->Prepared}} @dryrun;
    if (@scrips) {
        for my $scrip (grep $_->ActionObj->Action->isa('RT::Action::SendEmail'), @scrips) {
            my $action = $scrip->ActionObj->Action;
            for my $type (qw(To Cc Bcc)) {
                for my $addr ($action->$type()) {
                    if (grep {$addr->address eq $_} @{$action->{NoSquelch}{$type} || []}) {
                        $no_squelch{$type}{$addr->address} = $addr;
                    } else {
                        $headers{$type}{$addr->address} = $addr;
                    }
                }
            }
        }
    }

    my %squelched = HTML::Mason::Commands::ProcessTransactionSquelching( \%args );
    my $squelched_config = !( RT->Config->Get('SquelchedRecipients', $args{'CurrentUser'}) );

    # Unpack the addresses found and save
    my %recipients;
    for my $type (qw(To Cc Bcc)) {
        next unless keys %{$headers{$type}} or keys %{$no_squelch{$type}};

        for my $addr (sort {$a->address cmp $b->address} values %{$headers{$type}}) {
            push @{$recipients{$type}}, $addr->address;
        }
    }

    # One-time Ccs and Bccs are processed through email headers, so they won't be picked up
    # by running the action To, Cc, Bcc methods above. If passed, add them here.
    foreach my $one_time ( qw(To Cc Bcc) ){
        my @addresses = Email::Address->parse($args{"Update" . $one_time}) if $args{"Update" . $one_time};
        push @{$recipients{$one_time}}, @addresses;
    }

    RT::Logger->debug("Found some recipients") if %recipients;

    return \%recipients;
}

1;
