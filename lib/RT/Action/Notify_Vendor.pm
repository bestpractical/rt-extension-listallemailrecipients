package RT::Action::Notify;

use strict;
use warnings;
no warnings 'redefine';

=head1 Prepare

After the default Notify.pm SetRecipients and the SendEmail
prepare, the MIME object is created and populated. Use it to
pull email headers and add to the message body the list of
email addresses who will receive the email.

=cut

sub Prepare {
    my $self = shift;
    $self->SetRecipients();
    my $return = $self->SUPER::Prepare();

    # Now that the template is prepared, check for recipients and
    # add them to the template if needed.
    $self->AddRecipientsToEmail();
    return $return;
}

=head1 AddRecipientsToEmail

Inspect the created MIME object, pull out To and Cc headers,
and add the list of emails to the body of the email, replacing
the RT-INSERT-RECIPIENTS placeholder.

=cut

sub AddRecipientsToEmail {
    my $self = shift;
    my $ent = $self->TemplateObj->MIMEObj;
    my @parts;

    # Could be one plain text part or multiple parts with plain
    # text and html. Handle both.
    if ( $ent->mime_type and $ent->mime_type eq 'text/plain' ){
        push @parts, $ent;
    }
    else{
        ExtractParts({ Parts => \@parts, Entity => $ent });
    }

    foreach my $part (@parts){
        $RT::Logger->info("Working on email part with type: " . $part->mime_type)
            if $part->mime_type;
        next unless $part->mime_type eq 'text/plain'
            or $part->mime_type eq 'text/html';

        # Read the (unencoded) body data
        my @original;
        if ( my $io = $part->open("r") ) {
            while ( my $line = $io->getline ) {
                push @original, $line if defined $line;
            }
            $io->close;
        }

        # Write back the message, replacing the recipient
        # placeholder with the actual recipient list.
        if ( my $io = $part->open("w") ) {
            foreach my $line (@original) {

                if ( $line =~ /RT-INSERT-RECIPIENTS/ ){
                    # Replace with list of recipients and write to email
                    my $emails = '';
                    $emails = join ', ', $self->AddressesFromHeader('To'),
                        $self->AddressesFromHeader('Cc');

                    $RT::Logger->info("Replacing RT-INSERT-RECIPIENTS with $emails");
                    $line =~ s/(RT\-INSERT\-RECIPIENTS)/$emails/;
                }

                $io->print($line);
            }
            $io->close;
        }
    }

    return;
}

sub ExtractParts {
    my $args_ref = shift;
    my $parts_ref = $args_ref->{'Parts'};
    my $ent = $args_ref->{'Entity'};

    # Drill down into multipart message until there are no more parts
    foreach my $part ($ent->parts){
        if ( $part->parts ){
            ExtractParts({ Parts => $parts_ref, Entity => $part });
        }
        else{
            push @{$parts_ref}, $part
            if ($part->mime_type eq 'text/plain' or
                $part->mime_type eq 'text/html');
        }
    }
    return;
}

1;
