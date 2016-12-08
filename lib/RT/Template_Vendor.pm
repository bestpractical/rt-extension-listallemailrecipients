package RT::Template;

use strict;
use warnings;
no warnings qw(redefine);

# Copied from RT's core RT::Template::Parse to add a variable to the template.
sub Parse {
    my $self = shift;
    my ($rv, $msg);

    my @more_template_args = $self->AddTemplateArgs(@_);

    if (not $self->IsEmpty and $self->Content =~ m{^Content-Type:\s+text/html\b}im) {
        local $RT::Transaction::PreferredContentType = 'text/html';
        ($rv, $msg) = $self->_Parse(@_, @more_template_args);
    }
    else {
        ($rv, $msg) = $self->_Parse(@_, @more_template_args);
    }

    return ($rv, $msg) unless $rv;

    my $mime_type   = $self->MIMEObj->mime_type;
    if (defined $mime_type and $mime_type eq 'text/html') {
        $self->_DowngradeFromHTML(@_, @more_template_args);
    }

    return ($rv, $msg);
}

sub AddTemplateArgs {
    my $self = shift;
    my @more_template_args;
    push @more_template_args,
        'NotificationRecipientsTo' => $RT::Extension::ListAllEmailRecipients::NotificationRecipientsTo,
        'NotificationRecipientsCc' => $RT::Extension::ListAllEmailRecipients::NotificationRecipientsCc,
        'NotificationRecipientsBcc' => $RT::Extension::ListAllEmailRecipients::NotificationRecipientsBcc;

    return @more_template_args;
}

1;
