using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace MvcMusicStore.Models
{
    [Table("artists", Schema = "mvcmusicstore_dbo")]
    public class Artist
    {
        [Key]
        [Column("artistid")]
        public int ArtistId { get; set; }

        [Column("name")]
        public string Name { get; set; }
    }
}